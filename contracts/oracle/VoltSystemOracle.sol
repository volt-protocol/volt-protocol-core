// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Decimal} from "../external/Decimal.sol";
import {Constants} from "./../Constants.sol";
import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {IVoltSystemOracle} from "./IVoltSystemOracle.sol";

/// @notice contract that receives a fixed interest rate upon construction,
/// and then linearly interpolates that rate over a 30.42 day period into the VOLT price
/// after the oracle start time.
/// Interest compounds once per month.
/// @author Elliot Friedman
contract VoltSystemOracle is IVoltSystemOracle, CoreRefV2 {
    using Decimal for Decimal.D256;

    /// ---------- Mutable Variables ----------

    /// @notice acts as an accumulator for interest earned in previous periods
    /// returns the oracle price from the end of the last period
    uint256 public oraclePrice;

    /// @notice start time at which point interest will start accruing, and the
    /// current ScalingPriceOracle price will be snapshotted and saved
    uint256 public periodStartTime;

    /// ---------- Mutable Variable ----------

    /// @notice current amount that oracle price is inflating by monthly in basis points
    uint256 public monthlyChangeRateBasisPoints;

    /// ---------- Immutable Variable ----------

    /// @notice the time frame over which all changes in the APR are applied
    /// one month was chosen because this is a temporary oracle
    uint256 public constant TIMEFRAME = 30.42 days;

    /// @param _monthlyChangeRateBasisPoints monthly change rate in the Volt price
    /// @param _periodStartTime start time at which oracle starts interpolating prices
    /// @param _oraclePrice starting oracle price
    constructor(
        address _core,
        uint256 _monthlyChangeRateBasisPoints,
        uint256 _periodStartTime,
        uint256 _oraclePrice
    ) CoreRefV2(_core) {
        monthlyChangeRateBasisPoints = _monthlyChangeRateBasisPoints;
        periodStartTime = _periodStartTime;
        oraclePrice = _oraclePrice;
    }

    // ----------- Getter -----------

    /// @notice get the current scaled oracle price
    /// applies the change rate smoothly over a 30.42 day period
    /// scaled by 18 decimals
    // prettier-ignore
    function getCurrentOraclePrice() public view override returns (uint256) {
        uint256 cachedStartTime = periodStartTime; /// save a single warm SLOAD if condition is false
        if (cachedStartTime >= block.timestamp) { /// only accrue interest after start time
            return oraclePrice;
        }

        uint256 cachedOraclePrice = oraclePrice; /// save a single warm SLOAD by using the stack
        uint256 timeDelta = Math.min(block.timestamp - cachedStartTime, TIMEFRAME);
        uint256 pricePercentageChange = cachedOraclePrice * monthlyChangeRateBasisPoints / Constants.BASIS_POINTS_GRANULARITY;
        uint256 priceDelta = pricePercentageChange * timeDelta / TIMEFRAME;

        return cachedOraclePrice + priceDelta;
    }

    /// @notice function to get the current oracle price for the OracleRef contract
    /// valid is always true, price expressed as a decimal.
    function read()
        external
        view
        returns (Decimal.D256 memory price, bool valid)
    {
        uint256 currentPrice = getCurrentOraclePrice();

        price = Decimal.from(currentPrice).div(1e18);
        valid = true;
    }

    /// ------------- Public State Changing API -------------

    /// @notice public function that allows compounding of interest after duration has passed
    /// Sets accumulator to the current accrued interest, and then resets the timer.
    function compoundInterest() external override {
        require(
            block.timestamp >= periodStartTime + TIMEFRAME,
            "VoltSystemOracle: not past end time"
        );

        _compoundInterest();
    }

    /// @notice update the change rate in basis points
    /// callable only by the governor
    /// when called, interest accrued is compounded and then new rate is set
    function updateChangeRateBasisPoints(
        uint256 newMonthlyChangeRateBasisPoints
    ) external override onlyGovernor {
        _compoundInterest(); /// compound interest before updating change rate

        uint256 oldChangeRateBasisPoints = monthlyChangeRateBasisPoints;
        monthlyChangeRateBasisPoints = newMonthlyChangeRateBasisPoints;

        emit ChangeRateUpdated(
            oldChangeRateBasisPoints,
            newMonthlyChangeRateBasisPoints
        );
    }

    /// @notice helper function to compound interest
    function _compoundInterest() private {
        /// first set Oracle Price to interpolated value
        oraclePrice = getCurrentOraclePrice();

        /// set periodStartTime to periodStartTime + timeframe,
        /// this is equivalent to init timed, which wipes out all unaccumulated compounded interest
        /// and cleanly sets the start time.
        periodStartTime = periodStartTime + TIMEFRAME;

        emit InterestCompounded(periodStartTime, oraclePrice);
    }
}
