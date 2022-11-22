// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {PCVOracle} from "./PCVOracle.sol";
import {CoreRefV2} from "./../refs/CoreRefV2.sol";
import {DynamicVoltRateModel} from "./DynamicVoltRateModel.sol";

/// @notice contract that linearly interpolates VOLT rate over a year
/// into the VOLT price after the oracle start time.
/// The VOLT rate is dynamic and depends on a DynamicVoltRateModel and
/// the current ratio of liquid reserves in the system.
/// When PCV allocations change, this contract is notified and the oracle
/// start time updates, creating a new interpolation over 1 year.
/// @author Eswak, Elliot Friedman
contract DynamicVoltSystemOracle is CoreRefV2 {
    /// ------------- Events ---------------

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

    /// ---------- Mutable Variables ----------

    /// @notice Start time at which point interest will start accruing, and the
    /// current ScalingPriceOracle price will be snapshotted and saved.
    uint64 public periodStartTime;

    /// @notice Acts as an accumulator for interest earned in previous periods
    /// returns the oracle price from the end of the last period.
    uint192 public periodStartOraclePrice;

    /// @notice Current amount that oracle price is inflating by (APR, 18 decimals).
    /// This is set by governance. This is not actual rate Volt increases by, as it
    /// does not include the boost eventually returned by the DynamicVoltRateModel.
    uint256 public baseChangeRate;

    /// @notice Actual amount that oracle price is inflating by (APR, 18 decimals)
    /// derived from base rate volt price interpolates by this amount.
    uint256 public actualChangeRate;

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
    /// @param _previousOracle to get the starting oracle price from
    constructor(
        address _core,
        uint256 _baseChangeRate,
        uint256 _actualChangeRate,
        uint64 _periodStartTime,
        address _rateModel,
        address _previousOracle
    ) CoreRefV2(_core) {
        baseChangeRate = _baseChangeRate;
        actualChangeRate = _actualChangeRate;
        rateModel = _rateModel;
        // SafeCast not needed because max value of uint192 is 6e57
        uint192 currentOraclePrice = uint192(
            DynamicVoltSystemOracle(_previousOracle).getCurrentOraclePrice()
        );
        periodStartTime = _periodStartTime;
        periodStartOraclePrice = currentOraclePrice;
    }

    // ----------- Getters -----------

    /// @notice Get the current scaled oracle price.
    /// Applies the change rate linearly over {TIMEFRAME}.
    /// The value is expressed with 18 decimals.
    // prettier-ignore
    function getCurrentOraclePrice() public view returns (uint256) {
        uint256 cachedStartTime = periodStartTime; /// save a single warm SLOAD if condition is false
        if (cachedStartTime >= block.timestamp) { /// only accrue interest after start time
            return periodStartOraclePrice;
        }

        uint256 cachedOraclePrice = periodStartOraclePrice; /// save a single warm SLOAD by using the stack
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
            PCVOracle(pcvOracle).lastLiquidVenuePercentage()
        );
        uint256 oldActualChangeRate = actualChangeRate; // SLOAD
        actualChangeRate = newActualChangeRate; // SSTORE
        emit ActualRateUpdated(
            block.timestamp,
            oldActualChangeRate,
            newActualChangeRate
        );
    }

    /// @notice Set the reference to the Rate Model.
    /// Callable only by governor.
    /// @param newRateModel address of the new rate model.
    function setRateModel(address newRateModel) external onlyGovernor {
        address oldRateModel = rateModel; // SLOAD
        rateModel = newRateModel; // SSTORE
        // emit event
        emit RateModelUpdated(block.timestamp, oldRateModel, newRateModel);
    }

    /// ------------- PCV Oracle Only API -------------

    /// @notice Only callable by the PCV Oracle, updates the actual rate.
    /// @param liquidPercentage the percentage of PCV that is liquid,
    /// expressed with 18 decimals.
    /// @dev this function does not need the `isGlobalReentrancyLocked` modifier,
    /// because it is only called from the PCVOracle, either through the functions
    /// `updateLiquidBalance` or `updateIlliquidBalance`, that have the modifier,
    /// or from `addVenues` that is a governor-only action that will only execute
    /// during DAO proposals.
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
        // first, read values
        uint192 currentOraclePrice = uint192(getCurrentOraclePrice());
        uint64 currentBlockTime = uint64(block.timestamp);

        // then, do SSTORE
        periodStartTime = currentBlockTime;
        periodStartOraclePrice = currentOraclePrice;

        emit InterestCompounded(currentBlockTime, currentOraclePrice);
    }
}
