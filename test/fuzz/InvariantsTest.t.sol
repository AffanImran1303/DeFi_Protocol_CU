//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Test,console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract InvariantsTest is StdInvariant, Test{
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;

    function setUp() external{
        deployer=new DeployDSC();
        (dsc, dsce, config)=deployer.run();
        (,,weth,wbtc,)=config.activeNetworkConfig();
        targetContract(address(dsce));
    }
    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view{
        uint256 totalSupply= dsc.totalSupply();
        uint256 totalWethDeposited=IERC20(weth).balanceOf(address(dsce));
        uint256 totalWbtcDeposited=IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethValue=dsce.getUsdValue(weth,totalWethDeposited);
        uint256 wbtcValue=dsce.getUsdValue(wbtc,totalWbtcDeposited);

        console.log("Weth Value:",wethValue);
        console.log("Wbtc Value:",wbtcValue);
        console.log("total supply:",totalSupply);
        assert(wethValue+wbtcValue>=totalSupply);
        // console.log("Weth Value:",wethValue,"Wbtc Value:",wbtcValue,"Total Supply:",totalSupply);
    }
 
}