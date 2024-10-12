//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

/**
    * @title OracleLib
    * @author Patrick Collins
    * @notice This library is used to check the ChainLink Oracle for stale data.
    * If a price is stale, functions will revert, and render the DSCEngine unusable - this is by design.
    * We want the DSCEngine to freeze if prices become stable.
    *
    * So if the Chainlink network explodes and you have a lot of money locked in the protocol ... too bad.
 */

import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.4/interfaces/AggregatorV3Interface.sol";

 library OracleLib{

    error OracleLib_StalePrice();
    uint256 private constant TIMEOUT=3 hours;

    function staleCheckLatestRoundData(AggregatorV3Interface pricefeed) public view returns(uint80, int256, uint256, uint256, uint80){
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)=pricefeed.latestRoundData();
        uint256 secondsSince=block.timestamp-updatedAt;
        if(secondsSince>TIMEOUT)revert OracleLib_StalePrice();

        return (roundId, answer,startedAt, updatedAt, answeredInRound);
    
    }
 }