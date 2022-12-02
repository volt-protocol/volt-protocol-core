// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IOracleV2} from "./IOracleV2.sol";

interface IDynamicVoltSystemOracle is IOracleV2 {
    /// @notice Event emitted when the Volt system oracle compounds.
    /// Emits the end time of the period that completed and the new oracle price.
    event InterestCompounded(
        uint64 periodStartTime,
        uint192 periodStartOraclePrice
    );

    /// @notice Event emitted when the Volt system oracle base rate updates.
    event BaseRateUpdated(
        uint256 periodStart,
        uint256 oldRate,
        uint256 newRate
    );

    /// @notice Event emitted when the Volt system oracle actual rate updates.
    event ActualRateUpdated(
        uint256 periodStart,
        uint256 oldRate,
        uint256 newRate
    );

    /// @notice Event emitted when reference to the PCV Oracle updates.
    event PCVOracleUpdated(
        uint256 blockTime,
        address oldOracle,
        address newOracle
    );

    /// @notice Event emitted when reference to the Rate Model updates.
    event RateModelUpdated(
        uint256 blockTime,
        address oldRateModel,
        address newRateModel
    );

    /// ---------- View functions for state variables ----------

    function periodStartTime() external view returns (uint64);

    function periodStartOraclePrice() external view returns (uint192);

    function baseChangeRate() external view returns (uint256);

    function actualChangeRate() external view returns (uint256);

    function rateModel() external view returns (address);

    function TIMEFRAME() external view returns (uint256);

    /// --------- Helper function to read oracle value ---------

    function getCurrentOraclePrice() external view returns (uint256);

    /// ------------- Governor Only API ------------------------

    function updateBaseRate(uint256 newBaseChangeRate) external;

    function setRateModel(address newRateModel) external;

    /// ------------- PCV Oracle Only API ----------------------

    function updateActualRate(uint256 liquidPercentage) external;
}
