// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Constants} from "./../Constants.sol";
import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {IOracleV2} from "../oracle/IOracleV2.sol";
import {IVoltSystemOracle} from "./IVoltSystemOracle.sol";

/// @notice contract that receives a fixed interest rate upon construction,
/// and then linearly interpolates that rate over a 30.42 day period into the VOLT price
/// after the oracle start time.
/// Interest compounds once per month.
/// @author Elliot Friedman
contract VoltSystemOracle is IVoltSystemOracle, CoreRefV2, IOracleV2 {
    using SafeCast for *;

    /// ----------------------------------------
    /// ---------  Mutable Variables  ----------
    /// --------- Single Storage Slot ----------
    /// ----------------------------------------

    /// @notice acts as an accumulator for interest earned in previous periods
    /// returns the oracle price from the end of the last period
    uint200 private _oraclePrice;

    /// @notice start time at which point interest will start accruing, and the
    /// current ScalingPriceOracle price will be snapshotted and saved
    uint40 private _periodStartTime;

    /// @notice current amount that oracle price is inflating by monthly in basis points
    /// cannot be greater than 65,535 basis points per month
    uint16 private _monthlyChangeRateBasisPoints;

    /// ---------- Immutable Variable ----------

    /// @notice the time frame over which all changes in the APR are applied
    /// one month was chosen because this is a temporary oracle
    uint256 public constant TIMEFRAME = 30.42 days;

    /// @param _core reference
    /// @param startingMonthlyChangeRateBasisPoints monthly change rate in the Volt price
    /// @param startingPeriodStartTime start time at which oracle starts interpolating prices
    /// @param startingoraclePrice starting oracle price
    constructor(
        address _core,
        uint16 startingMonthlyChangeRateBasisPoints,
        uint40 startingPeriodStartTime,
        uint200 startingoraclePrice
    ) CoreRefV2(_core) {
        _monthlyChangeRateBasisPoints = startingMonthlyChangeRateBasisPoints;
        _periodStartTime = startingPeriodStartTime;
        _oraclePrice = startingoraclePrice;
    }

    // ----------- Getters -----------

    /// @notice get the current scaled oracle price
    /// applies the change rate smoothly over a 30.42 day period
    /// scaled by 18 decimals
    // prettier-ignore
    function getCurrentOraclePrice() public view override returns (uint256) {
        uint256 cachedStartTime = _periodStartTime; /// save a single warm SLOAD if condition is false
        if (cachedStartTime >= block.timestamp) { /// only accrue interest after start time
            return _oraclePrice;
        }

        uint256 cachedOraclePrice = _oraclePrice; /// save a single warm SLOAD by using the stack
        uint256 timeDelta = Math.min(block.timestamp - cachedStartTime, TIMEFRAME);
        uint256 pricePercentageChange = cachedOraclePrice * _monthlyChangeRateBasisPoints / Constants.BASIS_POINTS_GRANULARITY;
        uint256 priceDelta = pricePercentageChange * timeDelta / TIMEFRAME;

        return cachedOraclePrice + priceDelta;
    }

    /// @notice function to get the current oracle price for the OracleRef contract
    /// valid is always true, price expressed as a uint256 scaled by 1e18.
    function read() external view returns (uint256 price, bool valid) {
        price = getCurrentOraclePrice();
        valid = true;
    }

    /// @notice oracle price. starts off at 1e18 and compounds monthly
    /// acts as an accumulator for interest earned in previous epochs
    /// returns the oracle price from the end of the last period
    function oraclePrice() external view override returns (uint256) {
        return _oraclePrice;
    }

    /// @notice start time at which point interest will start accruing, and the
    /// current ScalingPriceOracle price will be snapshotted and saved
    function periodStartTime() external view override returns (uint256) {
        return _periodStartTime;
    }

    /// @notice current amount that oracle price is inflating by monthly in basis points
    /// does not support negative rates because PCV will not be deposited into negatively
    /// yielding venues.
    function monthlyChangeRateBasisPoints()
        external
        view
        override
        returns (uint256)
    {
        return _monthlyChangeRateBasisPoints;
    }

    /// ------------- Public State Changing API -------------

    /// @notice public function that allows compounding of interest after duration has passed
    /// Sets accumulator to the current accrued interest, and then resets the timer.
    function compoundInterest() external override {
        require(
            block.timestamp >= _periodStartTime + TIMEFRAME,
            "VoltSystemOracle: not past end time"
        );

        _compoundInterest();
    }

    /// @notice update the change rate in basis points
    /// callable only by the governor
    /// when called, interest accrued is compounded and then new rate is set
    function updateChangeRateBasisPoints(
        uint16 newMonthlyChangeRateBasisPoints
    ) external override onlyGovernor {
        _compoundInterest(); /// compound interest before updating change rate

        uint256 oldChangeRateBasisPoints = _monthlyChangeRateBasisPoints;
        _monthlyChangeRateBasisPoints = newMonthlyChangeRateBasisPoints
            .toUint16();

        emit ChangeRateUpdated(
            oldChangeRateBasisPoints,
            newMonthlyChangeRateBasisPoints
        );
    }

    /// @notice helper function to compound interest
    function _compoundInterest() private {
        uint200 newOraclePrice = uint200(getCurrentOraclePrice());
        uint40 newStartTime = uint40(_periodStartTime + TIMEFRAME);

        /// SSTORE
        /// first set Oracle Price to interpolated value
        /// this should never remove accuracy as price would need to be greater than
        /// 1606938044000000000000000000000000000000000000000000000000000
        /// for this to fail.
        /// starting price -> 1000000000000000000
        _oraclePrice = newOraclePrice;

        /// set periodStartTime to periodStartTime + timeframe,
        /// this is equivalent to init timed, which wipes out all unaccumulated compounded interest
        /// and cleanly sets the start time.
        _periodStartTime = newStartTime;

        emit InterestCompounded(newStartTime, newOraclePrice);
    }
}
