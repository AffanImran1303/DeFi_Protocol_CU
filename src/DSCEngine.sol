// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions


/*
* @title DSCEngine
* The system is designed to be as minimal as possible, and have tokens maintain a 1 token == $1 peg at all times.
* This is a stablecoin with following properties:
* - Exogenously Collateralized
* - Dollar Pegged
* - Algorithmically Stable
*
* It is similar to DAI, if DAI had no governance, no fees, and was backed by only WETH and WBTC
*
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
*/

pragma solidity ^0.8.24;


import {OracleLib} from "src/libraries/OracleLib.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.4/interfaces/AggregatorV3Interface.sol";

contract DSCEngine is ReentrancyGuard{

    using OracleLib for AggregatorV3Interface;

    ///////////////////
    //     Errors    //
    ///////////////////

    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine_TokenNotAllowed(address token);
    error DSCEngine_TransferFailed();
    error DSCEngine_BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine_MintFailed();
    error DSCEngine_HealthFactorOk();
    error DSCEngine_HealthFactorNotImproved();

    /////////////////////////
    //   State Variables   //
    /////////////////////////

    mapping(address token => address priceFeed) private s_priceFeeds;
    DecentralizedStableCoin private immutable i_gxsc;
    mapping(address user=>mapping(address token=> uint256 amount))private s_collateralDeposited;
    mapping(address user=>uint256 amountDscToMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    uint256 private constant ADDITIONAL_FEED_PRECISION=1e10;
    uint256 private constant PRECISION=1e18;
    uint256 private constant LIQUIDATION_THRESHOLD=50;
    uint256 private constant LIQUIDATION_PRECISION=100;
    uint256 private constant MIN_HEALTH_FACTOR=1e18;
    uint256 private constant LIQUIDATION_BONUS=10;

    ////////////////
    //   Events   //
    ////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount);
    ///////////////////
    //   Modifiers   //
    ///////////////////

    modifier moreThanZero(uint256 amount){
        if(amount<=0){
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }
    modifier isAllowedToken(address token){
        if(s_priceFeeds[token]==address(0)){
            revert DSCEngine_TokenNotAllowed(token);
        }
        _;
    }
 
    ///////////////////
    //   Functions   //
    ///////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress){
        if(tokenAddresses.length!=priceFeedAddresses.length){
            revert DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for(uint256 i=0;i<tokenAddresses.length;i++){
            s_priceFeeds[tokenAddresses[i]]=priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_gxsc=DecentralizedStableCoin(dscAddress);
    }

    ///////////////////////////
    //   External Functions  //
    ///////////////////////////

function depositCollaterAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint)external{
        depositCollateral(tokenCollateralAddress,amountCollateral);
        mintDSC(amountDscToMint);

    }

    /*
    * @param tokenCollateralAddress: The ERC20 token address of the collateral user will deposit.
    * @param amountCollateral: The amount of collateral user is depositing
*/
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)public moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant{
        s_collateralDeposited[msg.sender][tokenCollateralAddress]+=amountCollateral;
        emit CollateralDeposited(msg.sender,tokenCollateralAddress,amountCollateral);
        bool success=IERC20(tokenCollateralAddress).transferFrom(msg.sender,address(this),amountCollateral);
        if(!success){
            revert DSCEngine_TransferFailed();
        }
    
    }
    function mintDSC(uint256 amountDscToMint)public moreThanZero(amountDscToMint) nonReentrant{
        s_DSCMinted[msg.sender]+=amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted=i_gxsc.mint(msg.sender,amountDscToMint);
        if(!minted){
            revert DSCEngine_MintFailed();
        }
    }

    ///////////////////////////////////////////
    //   Private & Internal View Functions   //
    ///////////////////////////////////////////

    function _redeemCollateral(address from, address to,address tokenCollateralAddress, uint256 amountCollateral)private{
        s_collateralDeposited[from][tokenCollateralAddress]-=amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20 (tokenCollateralAddress).transfer(to,amountCollateral);
        if(!success){
            revert DSCEngine_TransferFailed();
        }
    }
    function _revertIfHealthFactorIsBroken(address user)internal view {
        uint256 userHealthFactor=_healthFactor(user);
        if(userHealthFactor<MIN_HEALTH_FACTOR){
            revert DSCEngine_BreaksHealthFactor(userHealthFactor);
        }
    }
    /*
    * Returns how close to liquidation a user is
    * If a user goes below 1, then they can be liquidated.
    */

    function _healthFactor(address user) private view returns(uint256){
        (uint256 totalDscMinted,uint256 collateralValueInUsd)=_getAccountInformation(user);
        uint256 collateralAdjustedForThreshold=(collateralValueInUsd*LIQUIDATION_THRESHOLD)/LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold*PRECISION)/totalDscMinted;
    }

    function _getAccountInformation(address user) private view returns(uint256 totalDscMinted, uint256 collateralValueInUsd){
        totalDscMinted=s_DSCMinted[user];
        collateralValueInUsd=getAccountCollateralValue(user);
    }
    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)internal pure returns(uint256){
        if(totalDscMinted==0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold=(collateralValueInUsd*LIQUIDATION_THRESHOLD)/LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold*PRECISION)/totalDscMinted;
    }

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private moreThanZero(amountDscToBurn){
        s_DSCMinted[onBehalfOf]-=amountDscToBurn;
        bool success = i_gxsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if(!success){
            revert DSCEngine_TransferFailed();
        }
        i_gxsc.burn(amountDscToBurn);
    }

        //////////////////////////////////////////
        //   Public & External View Functions   //
        //////////////////////////////////////////

    function getAccountInformation(address user) external view returns(uint256 totalDscMinted, uint256 collateralValueInUsd){
        (totalDscMinted,collateralValueInUsd)=_getAccountInformation(user);
    }
    
    function getAccountCollateralValue(address user) public view returns(uint256 totalCollateralValueInUsd){
        for(uint256 i=0;i<s_collateralTokens.length;i++){
            address token=s_collateralTokens[i];
            uint256 amount=s_collateralDeposited[user][token];
            totalCollateralValueInUsd+=getUsdValue(token,amount);
        }
        return totalCollateralValueInUsd;

    }
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns(uint256){
        AggregatorV3Interface priceFeed= AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,)=priceFeed.staleCheckLatestRoundData();

        return (usdAmountInWei*PRECISION)/(uint256(price)*ADDITIONAL_FEED_PRECISION);
    }

    function getUsdValue(address token, uint256 amount)public view returns(uint256){
        AggregatorV3Interface priceFeed=AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,)=priceFeed.staleCheckLatestRoundData();
        return ((uint256(price*1e10)*ADDITIONAL_FEED_PRECISION)*amount)/PRECISION;
    }
    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)external{
        burnDSC(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)public moreThanZero(amountCollateral) nonReentrant{
        _redeemCollateral(msg.sender,msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
       
        // s_collateralDeposited[msg.sender][tokenCollateralAddress]-=amountCollateral;
        // emit CollateralRedeemed(msg.sender,tokenCollateralAddress,amountCollateral);

        bool success=IERC20(tokenCollateralAddress).transfer(msg.sender,amountCollateral);
        if(!success){
            revert DSCEngine_TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }
    function burnDSC(uint256 amount)public moreThanZero(amount){
        _burnDsc(amount,msg.sender,msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
        // s_DSCMinted[msg.sender]-=amount;
        // bool success = i_gxsc.transferFrom(msg.sender,address(this),amount);
        // if(!success){
        //     revert DSCEngine_TransferFailed();
        // }
        // i_gxsc.burn(amount);
        // _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
* @param collateral: The ERC20 token address of the collateral, that you're going to take from the user who is insolvent.
* In return, burn your DSC to pay off their debt, but you don't pay off your own.
* @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
* @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
*
* @notice: You can partially liquidate a user.
* @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
* @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this
to work.
* @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate
anyone.
* For example, if the price of the collateral plummeted before anyone could be liquidated.
*/
    function liquidate(address collateral, address user,uint256 debtToCover)external moreThanZero(debtToCover) nonReentrant{
        uint256 startingUserHealthFactor=_healthFactor(user);
        if(startingUserHealthFactor>MIN_HEALTH_FACTOR){
            revert DSCEngine_HealthFactorOk();
        }
        uint256 tokenAmountFromDebtCovered=getTokenAmountFromUsd(collateral,debtToCover);
        uint256 bonusCollateral=(tokenAmountFromDebtCovered*LIQUIDATION_BONUS)/LIQUIDATION_PRECISION;
        uint256 totalCollateralRedeemed=tokenAmountFromDebtCovered+bonusCollateral;

        _redeemCollateral(user, msg.sender,collateral,totalCollateralRedeemed);
        _burnDsc(debtToCover,user,msg.sender);

        uint256 endingUserHealthFactor=_healthFactor(user);
        if(endingUserHealthFactor<=startingUserHealthFactor){
            revert DSCEngine_HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }
    function getPrecision() external pure returns(uint256){
        return PRECISION;
    }
    function getAdditionalFeedPrecision() external pure returns(uint256){
        return ADDITIONAL_FEED_PRECISION;
    }
    function getLiquidationThreshold()external pure returns(uint256){
        return LIQUIDATION_THRESHOLD;
    }
    function getLiquidationBonus()external pure returns(uint256){
        return LIQUIDATION_BONUS;
    }
    function getLiquidationPrecision()external pure returns(uint256){
        return MIN_HEALTH_FACTOR;
    }
    function getCollateralTokens()external view returns (address[] memory){
        return s_collateralTokens;
    }
    function getDsc()external view returns(address){
        return address(i_gxsc);
    }
    function getCollateralTokenPriceFeed(address token) external view returns(address){
        return s_priceFeeds[token];
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns(uint){
        return s_collateralDeposited[user][token];
    }

    function getHealthFactor(address user) external view returns(uint256){
        return _healthFactor(user);
    }
    function getHealthFactor()external{}

    
}