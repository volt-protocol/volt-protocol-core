// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Constants} from "./../Constants.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IVoltSystemOracle} from "./IVoltSystemOracle.sol";

/// @notice contract that receives a fixed interest rate upon construction,
/// and then linearly interpolates that rate over a 1 year period into the VOLT price
/// after the oracle start time.
/// Interest can compound annually. Assumption is that this oracle will only be used until
/// Volt 2.0 ships. Maximum amount of compounding periods on this contract at 2% APR
/// is 6192 years, which is more than enough for this use case.
/// @author Elliot Friedman
contract VoltSystemOracle is IVoltSystemOracle {
    /// ---------- Mutable Variables ----------

    /// @notice acts as an accumulator for checkpointing interest earned in previous periods
    uint256 public override oraclePrice;

    /// @notice period start time at which point interest will start accruing
    uint256 public override periodStartTime;

    /// ---------- Immutable Variables ----------

    /// @notice current amount that oracle price is inflating by yearly in basis points
    uint256 public immutable annualChangeRateBasisPoints;

    /// @notice the time frame over which all changes in the APR are applied
    /// one year was chosen because this is a temporary oracle
    uint256 public constant override TIMEFRAME = 365 days;

    /// @param _annualChangeRateBasisPoints yearly change rate in the Volt price
    /// @param _periodStartTime start time at which oracle starts interpolating prices
    /// @param _oraclePrice starting oracle price
    constructor(
        uint256 _annualChangeRateBasisPoints,
        uint256 _periodStartTime,
        uint256 _oraclePrice
    ) {
        annualChangeRateBasisPoints = _annualChangeRateBasisPoints;
        periodStartTime = _periodStartTime;
        oraclePrice = _oraclePrice;
    }

    // ----------- Getters -----------

    /// @notice get the current scaled oracle price
    /// applies the change rate smoothly over a 365 day period
    /// scaled by 18 decimals
    // prettier-ignore
    function getCurrentOraclePrice() public view override returns (uint256) {
        uint256 cachedStartTime = periodStartTime; /// save a single warm SLOAD if condition is false
        if (cachedStartTime >= block.timestamp) { /// only accrue interest after start time
            return oraclePrice;
        }

        uint256 cachedOraclePrice = oraclePrice; /// save a single warm SLOAD by using the stack
        uint256 timeDelta = Math.min(block.timestamp - cachedStartTime, TIMEFRAME);
        uint256 pricePercentageChange = cachedOraclePrice * annualChangeRateBasisPoints / Constants.BASIS_POINTS_GRANULARITY;
        uint256 priceDelta = pricePercentageChange * timeDelta / TIMEFRAME;

        return cachedOraclePrice + priceDelta;
    }

    /// @notice function that returns the end time of the current period
    function oracleEndTime() public view returns (uint256) {
        return periodStartTime + TIMEFRAME;
    }

    /// ------------- Public State Changing API -------------

    /// @notice public function that allows compounding of interest after duration has passed
    /// Sets accumulator to the current accrued interest, and then resets the timer.
    function compoundInterest() external override {
        uint256 periodEndTime = periodStartTime + TIMEFRAME; /// save a single warm SLOAD when writing to periodStartTime
        require(
            block.timestamp >= periodEndTime,
            "VoltSystemOracle: not past end time"
        );

        /// first set Oracle Price to interpolated value
        oraclePrice = getCurrentOraclePrice();

        /// set periodStartTime to periodStartTime + timeframe,
        /// this is equivalent to init timed, which wipes out all unaccumulated compounded interest
        /// and cleanly sets the start time.
        periodStartTime = periodEndTime;

        emit InterestCompounded(periodEndTime - TIMEFRAME, oraclePrice);
    }
}
