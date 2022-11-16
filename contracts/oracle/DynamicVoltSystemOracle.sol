// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {PCVOracle} from "./PCVOracle.sol";
import {CoreRefV2} from "./../refs/CoreRefV2.sol";
import {IVoltSystemOracle} from "./IVoltSystemOracle.sol";
import {DynamicVoltRateModel} from "./DynamicVoltRateModel.sol";

/// @notice contract that linearly interpolates VOLT rate over a year
/// into the VOLT price after the oracle start time.
/// The VOLT rate is dynamic and depends on a DynamicVoltRateModel and
/// the current ratio of liquid reserves in the system.
/// When PCV allocations change, this contract is notified and the oracle
/// start time updates, creating a new interpolation over 1 year.
/// @author Eswak, Elliot Friedman
contract DynamicVoltSystemOracle is CoreRefV2 {
    using SafeCast for *;

    /// @notice Event emitted when the Volt system oracle compounds.
    /// Emits the end time of the period that completed and the new oracle price.
    event InterestCompounded(uint256 periodStart, uint256 newOraclePrice);

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

    /// ---------- Mutable Variables ----------

    /// @notice Acts as an accumulator for interest earned in previous periods
    /// returns the oracle price from the end of the last period.
    uint256 public oraclePrice;

    /// @notice Start time at which point interest will start accruing, and the
    /// current ScalingPriceOracle price will be snapshotted and saved.
    uint256 public periodStartTime;

    /// @notice Current amount that oracle price is inflating by (APR, 18 decimals).
    /// This is set by governance. This is not actual rate Volt increases by, as it
    /// does not include the boost eventually returned by the DynamicVoltRateModel.
    uint256 public baseChangeRate;

    /// @notice Actual amount that oracle price is inflating by (APR, 18 decimals)
    /// derived from base rate volt price interpolates by this amount.
    uint256 public actualChangeRate;

    /// @notice Reference to the PCV oracle smart contract.
    address public pcvOracle;

    /// @notice Reference to the DynamicVoltRateModel smart contract.
    address public rateModel;

    /// ---------- Constant Variables ----------

    /// @notice The time frame over which all changes in the APR are applied.
    /// One year was chosen because this is a long time horizon, allowing for
    /// better precision in computations, and it is also an intuitive way to
    /// read the value for humans.
    uint256 public constant TIMEFRAME = 365.25 days;

    /// Assume that on construction the actualChangeRate passed is correct
    /// @param _core reference to core
    /// @param _baseChangeRate monthly change rate in the Volt price scaled by 1e18
    /// @param _actualChangeRate monthly change rate in the Volt price scaled by 1e18
    /// @param _periodStartTime start time at which oracle starts interpolating prices
    /// @param _rateModel dynamic volt rate model to use to compute actualChangeRate
    /// @param _oracle to get the starting oracle price from
    constructor(
        address _core,
        uint256 _baseChangeRate,
        uint256 _actualChangeRate,
        uint256 _periodStartTime,
        address _rateModel,
        address _oracle
    ) CoreRefV2(_core) {
        baseChangeRate = _baseChangeRate;
        actualChangeRate = _actualChangeRate;
        periodStartTime = _periodStartTime;
        rateModel = _rateModel;
        oraclePrice = IVoltSystemOracle(_oracle).getCurrentOraclePrice();
    }

    // ----------- Getters -----------

    /// @notice Get the current scaled oracle price.
    /// Applies the change rate linearly over {TIMEFRAME}.
    /// The value is expressed with 18 decimals.
    // prettier-ignore
    function getCurrentOraclePrice() public view returns (uint256) {
        uint256 cachedStartTime = periodStartTime; /// save a single warm SLOAD if condition is false
        if (cachedStartTime >= block.timestamp) { /// only accrue interest after start time
            return oraclePrice;
        }

        uint256 cachedOraclePrice = oraclePrice; /// save a single warm SLOAD by using the stack
        uint256 timeDelta = Math.min(block.timestamp - cachedStartTime, TIMEFRAME);
        uint256 periodPriceChange = cachedOraclePrice * actualChangeRate;
        uint256 priceDelta = periodPriceChange * timeDelta / TIMEFRAME / 1e18;

        return cachedOraclePrice + priceDelta;
    }

    /// ------------- Governor Only API -------------

    /// @notice Set the base VOLT rate.
    /// This will also refresh the actual VOLT rate.
    /// Callable only by governor.
    /// @param newBaseChangeRate new value for the baseChangeRate.
    function updateBaseRate(uint256 newBaseChangeRate) external onlyGovernor {
        /// first, compound interest
        _compoundInterest();

        uint256 oldBaseChangeRate = baseChangeRate; // SLOAD
        baseChangeRate = newBaseChangeRate; // SSTORE
        emit BaseRateUpdated(
            block.timestamp,
            oldBaseChangeRate,
            newBaseChangeRate
        );

        /// if too few liquid reserves, adjust rate up
        uint256 newActualChangeRate = DynamicVoltRateModel(rateModel).getRate(
            newBaseChangeRate,
            PCVOracle(pcvOracle).getLiquidVenuePercentage()
        );
        uint256 oldActualChangeRate = actualChangeRate; // SLOAD
        actualChangeRate = newActualChangeRate; // SSTORE
        emit ActualRateUpdated(
            block.timestamp,
            oldActualChangeRate,
            newActualChangeRate
        );
    }

    /// @notice Set the reference to the PCV oracle.
    /// Callable only by governor.
    /// @param newPcvOracle address of the new pcv oracle.
    function setPcvOracle(address newPcvOracle) external onlyGovernor {
        address oldPcvOracle = pcvOracle; // SLOAD
        pcvOracle = newPcvOracle; // SSTORE
        emit PCVOracleUpdated(block.timestamp, oldPcvOracle, newPcvOracle);
    }

    /// ------------- PCV Oracle Only API -------------

    /// @notice Only callable by the PCV Oracle, updates the actual rate.
    /// @param liquidPercentage the percentage of PCV that is liquid,
    /// expressed with 18 decimals.
    function updateActualRate(uint256 liquidPercentage) external {
        require(msg.sender == pcvOracle, "MGO: Not PCV Oracle");

        /// first, compound interest
        _compoundInterest();

        /// if too few liquid reserves, adjust rate up
        uint256 newActualChangeRate = DynamicVoltRateModel(rateModel).getRate(
            baseChangeRate,
            liquidPercentage
        );
        uint256 oldActualChangeRate = actualChangeRate; // SLOAD
        actualChangeRate = newActualChangeRate; // SSTORE
        emit ActualRateUpdated(
            block.timestamp,
            oldActualChangeRate,
            newActualChangeRate
        );
    }

    /// ------------- Helper Methods -------------

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
