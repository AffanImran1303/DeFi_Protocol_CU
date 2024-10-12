//SPDX-License-Identifier:MIT

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

pragma solidity ^0.8.24;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
*@title: DecentralizedStableCoin
*Collateral: Exogenous(ETH & BTC)
*Minting: Algorithmic
*Relative Stability: Pegged to USD
*
    This is the contract is the ERC20 implementation of our stablecoin system, meant to be goverened by DSCEngine
*/
contract DecentralizedStableCoin is ERC20Burnable, Ownable{

    error DecentralizedBlockGenixStableCoin_MustBeMoreThanZero();
    error DecentralizedBlockGenixStableCoin_BurnAmountExceedsBalance();
    error DecentralizedBlockGenixStableCoin_NotZeroAddress();

    constructor()ERC20("DecentralizedBlockGenixStableCoin","GXSC") Ownable(msg.sender){}

    function burn(uint256 _amount)public override onlyOwner{
        uint256 balance=balanceOf(msg.sender);
        if(_amount<=0){
            revert DecentralizedBlockGenixStableCoin_MustBeMoreThanZero();
        }
        if(balance<_amount){
            revert DecentralizedBlockGenixStableCoin_BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }
    function mint(address _to,uint256 _amount) external onlyOwner returns(bool){
        if(_to==address(0)){
            revert DecentralizedBlockGenixStableCoin_NotZeroAddress();
        }
        if(_amount<=0){
            revert DecentralizedBlockGenixStableCoin_MustBeMoreThanZero();
        }
        _mint(_to,_amount);
        return true;
        
    }
    
}
