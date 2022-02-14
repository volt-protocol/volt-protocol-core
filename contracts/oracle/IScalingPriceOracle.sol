// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

interface IScalingPriceOracle {
    function getCurrentOraclePrice() external view returns (uint256);
    function annualChangeRateBasisPoints() external view returns (int256);
    function chainlinkCPIOracle() external view returns (address);
    function oracleUpdateChangeRate(int256 newChangeRateBasisPoints) external;
}