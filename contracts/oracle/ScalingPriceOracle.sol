// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Timed} from "./../utils/Timed.sol";
import {Constants} from "./../Constants.sol";
import {CoreRef} from "contracts/refs/CoreRef.sol";
import {Deviation} from "contracts/utils/Deviation.sol";
import {IScalingPriceOracle} from "./IScalingPriceOracle.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @notice contract that receives a chainlink price feed and then linearly interpolates that rate over
/// a 1 month period into the VOLT price. Interest is compounded monthly when the rate is updated
/// @author Elliot Friedman
contract ScalingPriceOracle is Timed, IScalingPriceOracle, CoreRef, Deviation {
    using SafeCast for *;

    /// @notice current amount that oracle price is inflating/deflating by annually in basis points
    int256 public override annualChangeRateBasisPoints;

    /// @notice oracle price. starts off at 1e18
    uint256 public oraclePrice = 1e18;

    /// @notice address that is allowed to call in and update the current price
    address public override chainlinkCPIOracle;

    /// @notice event when Chainlink CPI oracle address is changed
    event ChainlinkCPIOracleUpdate(address oldChainLinkCPIOracle, address newChainlinkCPIOracle);

    /// @notice event when the annual change rate is updated
    event CPIAnnualChangeRateUpdate(int256 oldChangeRateBasisPoints, int256 newChangeRateBasisPoints);

    constructor(
        int256 _annualChangeRateBasisPoints,
        uint256 _maxDeviationThresholdBasisPoints,
        address coreAddress,
        address _chainlinkCPIOracle
    )
        Deviation(_maxDeviationThresholdBasisPoints)
        CoreRef(coreAddress)
        Timed(28 days) /// this duration should be 28 days as that is the minimum period of time between CPI monthly updates
    {
        annualChangeRateBasisPoints = _annualChangeRateBasisPoints;
        chainlinkCPIOracle = _chainlinkCPIOracle;

        /// start the timer
        _initTimed();
    }

    // ----------- Modifier -----------

    /// @notice restrict access to only the chainlink CPI Oracle
    modifier onlyChainlinkCPIOracle {
        require(msg.sender == chainlinkCPIOracle, "ScalingPriceOracle: caller is not chainlink oracle");
        _;
    }

    // ----------- Getter -----------

    /// @notice get the current scaled oracle price
    function getCurrentOraclePrice() public view override returns (uint256) {
        int256 oraclePriceInt = oraclePrice.toInt256();
        return SafeCast.toUint256(
            oraclePriceInt +
            (oraclePriceInt * annualChangeRateBasisPoints / Constants.BASIS_POINTS_GRANULARITY_INT * (block.timestamp - startTime).toInt256() / Constants.ONE_YEAR_INT)
        );
    }

    /// @notice return interest accrued per second
    function getInterestAccruedPerSecond() public view returns (int256) {
        return (
            oraclePrice.toInt256() *
            annualChangeRateBasisPoints /
            Constants.BASIS_POINTS_GRANULARITY_INT /
            Constants.ONE_YEAR_INT
        );
    }

    // ----------- Helpers -----------

    /// @notice internal helper method to lock in the current price.
    /// should only be used when changing the oracle price to a higher price
    /// compounds interest accumulated over the past time period
    function _updateOraclePrice() internal afterTimeInit {
        oraclePrice = getCurrentOraclePrice();
    }

    // ----------- Governor only state changing api -----------

    /// @notice function for priviledged roles to be able to patch new data into the system
    /// DO NOT USE unless chainlink data provider is down
    function updateOracleChangeRateGovernor(int256 newChangeRateBasisPoints) external onlyGovernor {
        require(
            isWithinDeviationThreshold(annualChangeRateBasisPoints, newChangeRateBasisPoints),
            "ScalingPriceOracle: new change rate is outside of allowable deviation"
        );

        /// compound interest at current rates
        _updateOraclePrice();

        int256 oldChangeRateBasisPoints = annualChangeRateBasisPoints;
        annualChangeRateBasisPoints = newChangeRateBasisPoints;

        emit CPIAnnualChangeRateUpdate(oldChangeRateBasisPoints, newChangeRateBasisPoints);
    }

    /// @notice function to update the oracle price and change rate basis points in an emergency
    /// ignores all compounding, checks and balances
    /// DO NOT USE unless there is an emergency
    /// @param newOraclePrice the new oracle price
    function emergencyUpdateOraclePrice(uint256 newOraclePrice) external onlyGuardianOrGovernor {
        int256 oldChangeRateBasisPoints = annualChangeRateBasisPoints;
        oraclePrice = newOraclePrice;
        annualChangeRateBasisPoints = 0;

        emit CPIAnnualChangeRateUpdate(oldChangeRateBasisPoints, 0);
    }

    /// @notice function for priviledged roles to be able to upgrade the oracle system address
    /// @param newChainlinkCPIOracle new chainlink CPI oracle
    function updateChainLinkCPIOracle(address newChainlinkCPIOracle) external onlyGovernorOrGuardianOrAdmin {
        address oldChainlinkCPIOracle = chainlinkCPIOracle;
        chainlinkCPIOracle = newChainlinkCPIOracle;

        emit ChainlinkCPIOracleUpdate(oldChainlinkCPIOracle, newChainlinkCPIOracle);
    }

    /// @notice function to compound interest after the time period has elapsed
    /// SHOULD NOT BE USED unless there is an upstream issue with our chainlink oracle that prevents data from flowing downstream
    function compoundInterest() external onlyGovernorOrGuardianOrAdmin {
        _updateOraclePrice();
    }

    /// @notice function to update the timed duration
    /// @param newPeriod the new duration which the oracle price can be updated
    function updatePeriod(uint256 newPeriod) external onlyGovernorOrAdmin {
        _setDuration(newPeriod);
    }

    // ----------- Chainlink CPI Oracle only state changing api -----------

    /// @notice function for chainlink oracle to be able to call in and change the rate
    /// @param newChangeRateBasisPoints the new annual interest rate applied to the chainlink oracle price
    function oracleUpdateChangeRate(int256 newChangeRateBasisPoints) external onlyChainlinkCPIOracle {
        /// compound the interest with the current rate
        /// this also checks that we are after the timer has expired, and then resets it
        _updateOraclePrice();

        /// if the oracle target is the same as last time, save an SSTORE
        if (newChangeRateBasisPoints == annualChangeRateBasisPoints) {
            return ;
        }

        int256 oldChangeRateBasisPoints = annualChangeRateBasisPoints;
        annualChangeRateBasisPoints = newChangeRateBasisPoints;

        emit CPIAnnualChangeRateUpdate(oldChangeRateBasisPoints, newChangeRateBasisPoints);
    }
}
