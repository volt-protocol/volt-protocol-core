// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Timed} from "./../utils/Timed.sol";
import {Constants} from "./../Constants.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IVoltSystemOracle} from "./IVoltSystemOracle.sol";
import {IScalingPriceOracle} from "./IScalingPriceOracle.sol";

/// @notice contract that receives a fixed interest rate upon construction,
/// and then linearly interpolates that rate over a 1 year period into the VOLT price.
/// Interest can compound annually.
/// @author Elliot Friedman
contract VoltSystemOracle is Timed, Initializable, IVoltSystemOracle {
    /// ---------- Mutable Price Variable ----------

    /// @notice oracle price. starts off at 1e18 and compounds once yearly
    /// acts as an accumulator for interest earned in previous periods
    uint256 public override oraclePrice = 1e18;

    /// ---------- Immutable Variables ----------

    /// @notice current amount that oracle price is inflating by yearly in basis points
    uint256 public immutable annualChangeRateBasisPoints;

    /// @notice the time frame over which all changes in the APR are applied
    /// one year was chosen because this is a temporary oracle
    uint256 public constant override TIMEFRAME = 365 days;

    /// @notice reference to the Scaling Price Oracle which will be used to set the starting
    /// oraclePrice once past the oracleStartTime
    IScalingPriceOracle public immutable scalingPriceOracle;

    /// @notice start time at which point interest will start accruing, and the
    /// point in time at which the current ScalingPriceOracle price will be
    /// snapshotted and saved
    uint256 public immutable oracleStartTime;

    /// @param _annualChangeRateBasisPoints yearly change rate in the Volt price
    /// @param _oracleStartTime start time at which oracle starts interpolating prices
    /// @param _scalingPriceOracle contract to get price from on initialization
    constructor(
        uint256 _annualChangeRateBasisPoints,
        uint256 _oracleStartTime,
        IScalingPriceOracle _scalingPriceOracle
    ) Timed(TIMEFRAME) {
        annualChangeRateBasisPoints = _annualChangeRateBasisPoints;
        oracleStartTime = _oracleStartTime;
        scalingPriceOracle = _scalingPriceOracle;

        /// init timed to set start time to current block timestamp
        /// this stops getCurrentOraclePrice from returning an incorect price before
        /// init is called
        _initTimed();
    }

    // ----------- Getters -----------

    /// @notice get the current scaled oracle price
    /// applies the change rate smoothly over a 365 day period
    /// scaled by 18 decimals
    // prettier-ignore
    function getCurrentOraclePrice() public view override returns (uint256) {
        uint256 cachedOraclePrice = oraclePrice; /// save a single warm SLOAD by using the stack
        uint256 timeDelta = Math.min(block.timestamp - startTime, TIMEFRAME);
        uint256 pricePercentageChange = cachedOraclePrice * annualChangeRateBasisPoints / Constants.BASIS_POINTS_GRANULARITY;
        uint256 priceDelta = pricePercentageChange * timeDelta / TIMEFRAME;

        return cachedOraclePrice + priceDelta;
    }

    /// ------------- Public State Changing API's -------------

    /// @notice function to initialize the contract after the OracleStartTime has passed
    function init() external override initializer {
        require(
            block.timestamp >= oracleStartTime,
            "VoltSystemOracle: not past start time"
        );

        startTime = oracleStartTime; /// init timed class, wiping any accrued interest
        oraclePrice = scalingPriceOracle.getCurrentOraclePrice(); /// set starting oracle price
    }

    /// @notice public function that allows compounding of interest after duration has passed
    /// Sets accumulator to the current accrued interest, and then resets the timer.
    function compoundInterest() external override afterTime {
        /// first set Oracle Price to interpolated value
        oraclePrice = getCurrentOraclePrice();
        /// set startTime to startTime + timeframe,
        /// this is equivalent to init timed, which wipes out all unaccumulated compounded interest
        /// and cleanly sets the start time.
        startTime += TIMEFRAME;

        emit InterestCompounded();
    }
}
