// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

interface IScalingPriceOracle {
    function timeFrame() external view returns (uint256);

    function getCurrentOraclePrice() external view returns (uint256);

    function monthlyChangeRateBasisPoints() external view returns (int256);

    function chainlinkCPIOracle() external view returns (address);

    function oracleUpdateChangeRate(int256 newChangeRateBasisPoints) external;
}
