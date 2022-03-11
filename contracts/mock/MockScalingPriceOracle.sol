// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Timed} from "./../utils/Timed.sol";
import {CoreRef} from "./../refs/CoreRef.sol";
import {Constants} from "./../Constants.sol";
import {Deviation} from "./../utils/Deviation.sol";
import {IScalingPriceOracle} from "./../oracle/IScalingPriceOracle.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @notice contract that receives a chainlink price feed and then linearly interpolates that rate over
/// a 1 month period into the VOLT price. Interest is compounded monthly when the rate is updated
/// @author Elliot Friedman
contract MockScalingPriceOracle is
    Timed,
    IScalingPriceOracle,
    CoreRef,
    Deviation
{
    using SafeCast for *;

    /// @notice the time frame over which all changes in CPI data are applied
    /// 28 days was chosen as that is the shortest length of a month
    uint256 public constant override timeFrame = 28 days;

    /// @notice current amount that oracle price is inflating/deflating by monthly in basis points
    int256 public override monthlyChangeRateBasisPoints;

    /// @notice oracle price. starts off at 1e18
    uint256 public oraclePrice = 1e18;

    /// @notice event when the monthly change rate is updated
    event CPIMonthlyChangeRateUpdate(
        int256 oldChangeRateBasisPoints,
        int256 newChangeRateBasisPoints
    );

    constructor(
        int256 _monthlyChangeRateBasisPoints,
        uint256 _maxDeviationThresholdBasisPoints,
        address coreAddress
    )
        Deviation(_maxDeviationThresholdBasisPoints)
        CoreRef(coreAddress)
        Timed(timeFrame) /// this duration is 28 days as that is the minimum period of time between CPI monthly updates
    {
        monthlyChangeRateBasisPoints = _monthlyChangeRateBasisPoints;
    }

    // ----------- Getters -----------

    /// @notice get the current scaled oracle price
    /// applies the change smoothly over a 28 day period
    function getCurrentOraclePrice() public view override returns (uint256) {
        int256 oraclePriceInt = oraclePrice.toInt256();
        return
            SafeCast.toUint256(
                oraclePriceInt +
                    ((((oraclePriceInt * monthlyChangeRateBasisPoints) /
                        Constants.BASIS_POINTS_GRANULARITY_INT) *
                        Math
                            .min(block.timestamp - startTime, timeFrame)
                            .toInt256()) / timeFrame.toInt256())
            );
    }

    /// @notice return interest accrued per second
    function getInterestAccruedPerSecond() public view returns (int256) {
        return ((oraclePrice.toInt256() * monthlyChangeRateBasisPoints) /
            Constants.BASIS_POINTS_GRANULARITY_INT /
            timeFrame.toInt256());
    }

    /// @notice no-op for compatibility with interface
    function chainlinkCPIOracle() external view override returns (address) {}

    // ----------- Helpers -----------

    /// @notice internal helper method to lock in the current price.
    /// should only be used when changing the oracle price to a higher price
    /// compounds interest accumulated over the past time period
    function _updateOraclePrice() internal afterTimeInit {
        oraclePrice = getCurrentOraclePrice();
    }

    // ----------- State changing api -----------

    /// @notice function to compound interest after the time period has elapsed
    /// SHOULD NOT BE USED unless there is an upstream issue with our chainlink oracle that prevents data from flowing downstream
    function compoundInterest() external onlyGuardianOrGovernor {
        _updateOraclePrice();
    }

    /// @notice function to update the timed duration
    /// @param newPeriod the new duration which the oracle price can be updated
    function updatePeriod(uint256 newPeriod) external {
        _setDuration(newPeriod);
    }

    /// @param newChangeRateBasisPoints the new monthly interest rate applied to the chainlink oracle price
    function oracleUpdateChangeRate(int256 newChangeRateBasisPoints) external {
        /// compound the interest with the current rate
        /// this also checks that we are after the timer has expired, and then resets it
        _updateOraclePrice();

        /// if the oracle target is the same as last time, save an SSTORE
        if (newChangeRateBasisPoints == monthlyChangeRateBasisPoints) {
            return;
        }

        int256 oldChangeRateBasisPoints = monthlyChangeRateBasisPoints;
        monthlyChangeRateBasisPoints = newChangeRateBasisPoints;

        emit CPIMonthlyChangeRateUpdate(
            oldChangeRateBasisPoints,
            newChangeRateBasisPoints
        );
    }
}
