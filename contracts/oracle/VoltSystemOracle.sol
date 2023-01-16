// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
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
contract VoltSystemOracle is
    IVoltSystemOracle,
    CoreRefV2,
    IOracleV2,
    Initializable
{
    using SafeCast for *;

    /// ----------------------------------------
    /// ---------  Mutable Variables  ----------
    /// --------- Single Storage Slot ----------
    /// ----------------------------------------

    /// @notice acts as an accumulator for interest earned in previous periods
    /// returns the oracle price from the end of the last period
    uint112 public oraclePrice;

    /// @notice current amount that oracle price is inflating by monthly in
    /// percentage terms scaled by 1e18
    uint112 public monthlyChangeRate;

    /// @notice start time at which point interest will start accruing, and the
    /// current ScalingPriceOracle price will be snapshotted and saved
    uint32 public periodStartTime;

    /// ---------- Immutable Variable ----------

    /// @notice the time frame over which all changes in the APR are applied
    /// one month was chosen because this is a temporary oracle
    uint256 public constant TIMEFRAME = 30.42 days;

    /// @param _core reference
    constructor(address _core) CoreRefV2(_core) {}

    // ----------- Initializer -----------

    /// @notice initializes the oracle, setting start time to the current block timestamp,
    /// start price gets set to the previous oracle's current price.
    /// change rate is provided by governance.
    /// @param previousOracle address of the previous oracle
    /// @param startingMonthlyChangeRate starting interest change rate of the oracle
    function initialize(
        address previousOracle,
        uint112 startingMonthlyChangeRate
    ) external override onlyGovernor initializer {
        uint256 startingOraclePrice = IVoltSystemOracle(previousOracle)
            .getCurrentOraclePrice();
        uint32 startingTime = block.timestamp.toUint32();

        require(
            startingOraclePrice <= type(uint112).max,
            "SafeCast: value doesn't fit in 112 bits"
        );

        uint112 currentOraclePrice = uint112(startingOraclePrice);

        /// SINGLE SSTORE
        oraclePrice = currentOraclePrice;
        periodStartTime = startingTime;
        monthlyChangeRate = startingMonthlyChangeRate;
    }

    // ----------- Getters -----------

    /// @notice get the current scaled oracle price
    /// applies the change rate smoothly over a 30.42 day period
    /// scaled by 18 decimals
    // prettier-ignore
    function getCurrentOraclePrice() public view override returns (uint256) {
        /// save a single warm SLOAD by reading from storage once
        uint256 cachedStartTime = periodStartTime;
        uint256 cachedOraclePrice = oraclePrice;
        uint256 cachedMonthlyChangeRate = monthlyChangeRate;

        if (cachedStartTime >= block.timestamp) { /// only accrue interest after start time
            return oraclePrice;
        }

        uint256 timeDelta = Math.min(block.timestamp - cachedStartTime, TIMEFRAME);
        uint256 priceChangeOverPeriod = cachedOraclePrice * cachedMonthlyChangeRate / Constants.ETH_GRANULARITY;
        uint256 priceDelta = priceChangeOverPeriod * timeDelta / TIMEFRAME;

        return cachedOraclePrice + priceDelta;
    }

    /// @notice function to get the current oracle price for the OracleRef contract
    /// valid is always true, price expressed as a uint256 scaled by 1e18.
    function read() external view returns (uint256 price, bool valid) {
        price = getCurrentOraclePrice();
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

    /// ------------- Governor Only State Changing API -------------

    /// @notice update the change rate, callable only by the governor
    /// when called, interest accrued is compounded and then new rate is set
    function updateChangeRate(
        uint112 newMonthlyChangeRate
    ) external override onlyGovernor {
        _compoundInterest(); /// compound interest before updating change rate

        uint256 oldChangeRateBasisPoints = monthlyChangeRate;
        monthlyChangeRate = newMonthlyChangeRate;

        emit ChangeRateUpdated(oldChangeRateBasisPoints, newMonthlyChangeRate);
    }

    /// ------------- Internal Helper -------------

    /// @notice helper function to compound interest
    function _compoundInterest() private {
        uint256 currentOraclePrice = getCurrentOraclePrice();
        require(
            currentOraclePrice <= type(uint112).max,
            "SafeCast: value doesn't fit in 112 bits"
        );

        uint112 newOraclePrice = uint112(currentOraclePrice);
        uint32 newStartTime = (periodStartTime + TIMEFRAME).toUint32();

        /// SSTORE
        /// first set Oracle Price to interpolated value
        /// this should never remove accuracy as price would need to be greater than
        /// 1606938044000000000000000000000000000000000000000000000000000
        /// for this to fail.
        /// starting price -> 1000000000000000000
        oraclePrice = newOraclePrice;

        /// set periodStartTime to periodStartTime + timeframe,
        /// this is equivalent to init timed, which wipes out all unaccumulated compounded interest
        /// and cleanly sets the start time.
        periodStartTime = newStartTime;

        emit InterestCompounded(newStartTime, newOraclePrice);
    }
}
