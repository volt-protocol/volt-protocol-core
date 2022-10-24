// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {CoreRefV2} from "./../refs/CoreRefV2.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IVoltSystemOracle} from "./IVoltSystemOracle.sol";

/// @notice contract that receives a fixed interest rate upon construction,
/// and then linearly interpolates that rate over a 30.42 day period into the VOLT price
/// after the oracle start time.
/// Interest can compound annually. Assumption is that this oracle will only be used until
/// Volt 2.0 ships. Maximum amount of compounding periods on this contract at 2% APR
/// is 6192 years, which is more than enough for this use case.
/// @author Elliot Friedman
/// TODO need to track TWAP of surplus buffer to PCV to determine the actual volt rate
contract MarketGovernanceOracle is CoreRefV2 {
    using SafeCast for *;

    /// @notice event emitted when the Volt system oracle compounds
    /// emits the end time of the period that completed and the new oracle price
    event InterestCompounded(uint256 periodStart, uint256 newOraclePrice);

    /// ---------- Mutable Variables ----------

    /// @notice acts as an accumulator for interest earned in previous periods
    /// returns the oracle price from the end of the last period
    uint256 public oraclePrice;

    /// @notice start time at which point interest will start accruing, and the
    /// current ScalingPriceOracle price will be snapshotted and saved
    uint256 public periodStartTime;

    /// @notice current amount that oracle price is inflating by monthly as a percent, scaled by 1e18
    /// set by governance, not actual rate Volt increases by
    uint256 public baseChangeRate;

    /// @notice actual amount that oracle price is inflating by monthly as a percent, scaled by 1e18
    /// derived from base rate volt price interpolates by this amount.
    uint256 public actualChangeRate;

    /// @notice reference to the PCV oracle smart contract
    address public pcvOracle;

    /// ---------- Immutable Variable ----------

    /// @notice the percentage at which the Volt rate will start going above the base rate
    uint256 public immutable liquidityJumpTarget;

    /// ---------- Constant Variables ----------

    /// @notice maximum amount that oracle price can inflate by monthly as a
    /// percentage, derived from base rate. 10% is max monthly price increase
    uint256 public constant maximumChangeRate = 1e17;

    /// @notice the time frame over which all changes in the APR are applied
    /// one month was chosen because this is a temporary oracle
    uint256 public constant TIMEFRAME = 30.42 days;

    /// @notice amount to scale
    uint256 public constant SCALE = 1e18;

    /// assume that on construction the actualChangeRate passed is correct
    /// @param _core reference to core
    /// @param _baseChangeRate monthly change rate in the Volt price scaled by 1e18
    /// @param _actualChangeRate monthly change rate in the Volt price scaled by 1e18
    /// @param _liquidityJumpTarget liquid to illquid percent where actual Volt rate increases
    /// @param _periodStartTime start time at which oracle starts interpolating prices
    /// @param _oracle to get the starting oracle price from
    constructor(
        address _core,
        uint256 _baseChangeRate,
        uint256 _actualChangeRate,
        uint256 _liquidityJumpTarget,
        uint256 _periodStartTime,
        address _oracle
    ) CoreRefV2(_core) {
        baseChangeRate = _baseChangeRate;
        actualChangeRate = _actualChangeRate;
        liquidityJumpTarget = _liquidityJumpTarget;
        periodStartTime = _periodStartTime;
        oraclePrice = IVoltSystemOracle(_oracle).getCurrentOraclePrice();
    }

    /// @notice only callable by the pcv oracle smart contract
    modifier onlyPCVOracle() {
        require(msg.sender == pcvOracle, "MGO: Not PCV Oracle");
        _;
    }

    // ----------- Getter -----------

    /// @notice get the current scaled oracle price
    /// applies the change rate smoothly over a 30.42 day period
    /// scaled by 18 decimals
    // prettier-ignore
    function getCurrentOraclePrice() public view returns (uint256) {
        uint256 cachedStartTime = periodStartTime; /// save a single warm SLOAD if condition is false
        if (cachedStartTime >= block.timestamp) { /// only accrue interest after start time
            return oraclePrice;
        }

        uint256 cachedOraclePrice = oraclePrice; /// save a single warm SLOAD by using the stack
        uint256 timeDelta = Math.min(block.timestamp - cachedStartTime, TIMEFRAME);
        /// todo validate this works the same as VoltSystemOracle in fuzz, unit and invariant tests
        uint256 periodPriceChange = cachedOraclePrice * actualChangeRate;
        uint256 priceDelta = periodPriceChange * timeDelta / TIMEFRAME / SCALE;

        return cachedOraclePrice + priceDelta;
    }

    /// ------------- Public State Changing API -------------

    /// @notice public function that allows compounding of interest after duration has passed
    /// Sets accumulator to the current accrued interest, and then resets the timer.
    function compoundInterest() external {
        uint256 periodEndTime = periodStartTime + TIMEFRAME; /// save a single warm SLOAD when writing to periodStartTime
        require(
            block.timestamp >= periodEndTime,
            "VoltSystemOracle: not past end time"
        );

        _compoundInterest();
    }

    /// ------------- Governor Only API -------------

    function updateBaseRate(uint256 _baseChangeRate) external onlyGovernor {
        _compoundInterest();

        baseChangeRate = _baseChangeRate;
        /// todo also set actual change rate basis points based on current liquidity profile
        /// todo add an event here
    }

    /// @notice function to set the reference to the PCV oracle
    function setPcvOracle(address _pcvOracle) external onlyGovernor {
        pcvOracle = _pcvOracle;

        /// todo emit an event here
    }

    /// TODO add modifier so that only PCV Oracle can call this function
    function updateActualRate(uint256 liquidPercentage) external onlyPCVOracle {
        /// if liquidity is fine, no-op
        if (liquidPercentage >= liquidityJumpTarget) {
            return;
        }
        /// first compound interest
        _compoundInterest();
        /// if too illiquid, adjust rate up
        /// find amount off target, figure out how much actual rate should be
        /// set actual rate
        actualChangeRate = calculateRate(liquidPercentage);

        /// todo emit an event
    }

    /// TODO verify this calculation with an invariant test, a differential test, a unit test, and a fuzz test
    /// @notice function used to calculate the new actual rate based on liquidity
    /// @param liquidPercentage is the percent of total PCV that is liquid
    /// @return the new actual rate based on liquidity profile in the Volt system
    function calculateRate(uint256 liquidPercentage)
        public
        view
        returns (uint256)
    {
        uint256 _liquidityJumpTarget = liquidityJumpTarget; /// save 2 warm SLOADs
        /// liquidity jump target is the lowest percentage liquid before Volt rate spikes
        /// if more liquid than jump target, just use base rate
        /// if less liquid than jump target, boost Volt rate
        /// max change rate is base rate, return base rate
        if (
            liquidPercentage >= liquidityJumpTarget ||
            maximumChangeRate == baseChangeRate
        ) {
            return baseChangeRate;
        }

        /// use LERP to discover PCM delta on top of base rate
        uint256 totalPossibleBoost = maximumChangeRate - baseChangeRate;

        /// example figures

        /// pcm boost can be between 0 and 1000,
        /// with 1000 being 100 basis points or 1% on top of the base rate
        /// totalPossibleBoost = 1000 pcm

        /// liquidPercentage = 1e17 = 10% liquid
        /// liquidityJumpTarget = 3e17
        /// jumpRateDelta = 2e17
        /// 2e17 * 1000 / 3e17

        /// this should never revert or be 0 because if liquidPercentage is equal to or greater than
        /// liquidityJumpTarget, then this function returns the base rate and stops execution
        uint256 jumpRateDelta = _liquidityJumpTarget - liquidPercentage;

        /// amount of percentage points to add atop the base Volt rate
        uint256 pcmBoost = (jumpRateDelta * totalPossibleBoost) /
            _liquidityJumpTarget;

        return pcmBoost + baseChangeRate;
    }

    /// TODO verify this calculation with an invariant test, a differential test, a unit test, and a fuzz test
    /// Both calculateRateLerp and calculateRate should return the same value for a given input
    /// @notice function used to calculate the new actual rate based on liquidity
    /// @param liquidPercentage is the percent of total PCV that is liquid
    /// @return the new actual rate based on liquidity profile in the Volt system
    function calculateRateLerp(uint256 liquidPercentage)
        public
        view
        returns (uint256)
    {
        uint256 _liquidityJumpTarget = liquidityJumpTarget; /// save 2 warm SLOADs
        /// liquidity jump target is the lowest percentage liquid before Volt rate spikes
        /// if more liquid than jump target, just use base rate
        /// if less liquid than jump target, boost Volt rate
        /// max change rate is base rate, return base rate
        if (
            liquidPercentage >= liquidityJumpTarget ||
            maximumChangeRate == baseChangeRate
        ) {
            return baseChangeRate;
        }

        /// total possible boost
        ///                           how far below min are we?
        ///                                                         divide by jump target
        /// (max yield - base yield) * (jump target - current percent) / jump target

        /// variables ///

        // /// delta below target = (jump target - current percent)

        /// max yield = 10%
        /// base yield/rate = 1%
        /// total possible yield boost = 9%
        /// target utilization = 30%
        /// current utilization = 10%

        /// yield at target = base rate, x1
        /// total possible boost = max yield - base yield, x2
        /// target utilization = 30% liquid, y1
        /// lowest utilization = 0% liquid, y2
        /// current utilization = 10% liquid, y value

        /// yield at target = base jump rate, y1 = 1%
        /// total possible boost = max yield - base yield, y2 = 9%
        /// target utilization = 30% liquid, x1 = 30%
        /// lowest utilization = 0% liquid, x2 = 0%
        /// current utilization = 10% liquid, x value

        /// calculate actual Volt rate
        uint256 finalRate = _calculateLinearInterpolation(
            liquidPercentage,
            _liquidityJumpTarget,
            0,
            baseChangeRate,
            maximumChangeRate
        );

        return finalRate;
    }

    /// ------------- Helper Method -------------

    /// Linear Interpolation Formula
    /// (y) = y1 + (x − x1) * ((y2 − y1) / (x2 − x1))
    /// @notice calculate linear interpolation and return ending price
    /// @param x is time value to calculate interpolation on
    /// @param x1 is starting time to calculate interpolation from
    /// @param x2 is ending time to calculate interpolation to
    /// @param y1 is starting price to calculate interpolation from
    /// @param y2 is ending price to calculate interpolation to
    function _calculateLinearInterpolation(
        uint256 x,
        uint256 x1,
        uint256 x2,
        uint256 y1,
        uint256 y2
    ) internal pure returns (uint256 y) {
        uint256 firstDeltaX = x1 > x ? x1 - x : x - x1;
        uint256 secondDeltaX = x2 > x1 ? x2 - x1 : x1 - x2;
        uint256 deltaY = y2 > y1 ? y2 - y1 : y1 - y2;
        uint256 product = (firstDeltaX * deltaY) / secondDeltaX;

        y = (product + y1);
    }

    function _compoundInterest() private {
        /// first set Oracle Price to interpolated value
        oraclePrice = getCurrentOraclePrice();

        /// set periodStartTime to periodStartTime + timeframe,
        /// this is equivalent to init timed, which wipes out all unaccumulated compounded interest
        /// and cleanly sets the start time.
        periodStartTime = block.timestamp;

        emit InterestCompounded(periodStartTime, oraclePrice);
    }
}
