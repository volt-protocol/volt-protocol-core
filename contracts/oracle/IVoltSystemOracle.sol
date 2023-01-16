// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

/// @notice interface for the Volt System Oracle
interface IVoltSystemOracle {
    // ----------- Getters -----------

    /// @notice function to get the current oracle price for the entire system
    function getCurrentOraclePrice() external view returns (uint256);

    /// @notice start time at which point interest will start accruing, and the
    /// current ScalingPriceOracle price will be snapshotted and saved
    function periodStartTime() external view returns (uint32);

    /// @notice oracle price. starts off at 1e18 and compounds monthly
    /// acts as an accumulator for interest earned in previous epochs
    /// returns the oracle price from the end of the last period
    function oraclePrice() external view returns (uint112);

    /// @notice current amount that oracle price is inflating by monthly in
    /// percentage terms scaled by 1e18
    function monthlyChangeRate() external view returns (uint112);

    /// @notice the time frame over which all changes in the APR are applied
    /// one month was chosen because this is a temporary oracle
    function TIMEFRAME() external view returns (uint256);

    // ----------- Public State Changing API -----------

    /// @notice public function that allows compounding of interest after duration has passed
    /// Sets accumulator to the current accrued interest, and then resets the timer.
    function compoundInterest() external;

    /// ------------- Governor Only State Changing API -------------

    /// @notice initializes the oracle, setting start time to the current block timestamp,
    /// start price gets set to the previous oracle's current price.
    /// change rate is provided by governance.
    /// @param previousOracle address of the previous oracle
    /// @param startingMonthlyChangeRate starting interest change rate of the oracle
    function initialize(
        address previousOracle,
        uint112 startingMonthlyChangeRate
    ) external;

    /// @notice update the change rate, callable only by the governor
    /// @param newMonthlyChangeRate interest rate to interpolate price
    function updateChangeRate(uint112 newMonthlyChangeRate) external;

    // ----------- Event -----------

    /// @notice event emitted when the Volt system oracle compounds
    /// emits the end time of the period that completed and the new oracle price
    event InterestCompounded(uint256 periodStart, uint256 newOraclePrice);

    /// @notice emitted when Volt system oracle change rate updates
    event ChangeRateUpdated(
        uint256 oldChangeRateBasisPoints,
        uint256 newChangeRateBasisPoints
    );
}
