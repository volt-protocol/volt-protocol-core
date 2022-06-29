// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {IScalingPriceOracle} from "./IScalingPriceOracle.sol";

/// @notice interface for the Volt System Oracle
interface IVoltSystemOracle {
    // ----------- Getters -----------

    /// @notice reference to the scaling price oracle
    function scalingPriceOracle() external view returns (IScalingPriceOracle);

    /// @notice function to get the current oracle price for the entire system
    function getCurrentOraclePrice() external view returns (uint256);

    /// @notice start time at which point interest will start accruing, and the
    /// current ScalingPriceOracle price will be snapshotted and saved
    function oracleStartTime() external view returns (uint256);

    /// @notice oracle price. starts off at 1e18 and compounds yearly
    /// acts as an accumulator for interest earned in previous periods
    function oraclePrice() external view returns (uint256);

    /// @notice current amount that oracle price is inflating by yearly in basis points
    function annualChangeRateBasisPoints() external view returns (uint256);

    /// @notice the time frame over which all changes in the APR are applied
    /// one year was chosen because this is a temporary oracle
    function TIMEFRAME() external view returns (uint256);

    // ----------- Public state changing api -----------

    /// @notice function to initialize the contract after the OracleStartTime has passed
    function init() external;

    /// @notice public function that allows compounding of interest after duration has passed
    /// Sets accumulator to the current accrued interest, and then resets the timer.
    function compoundInterest() external;

    /// @notice event emitted when the Volt system oracle compounds
    event InterestCompounded();
}
