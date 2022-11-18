// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

/// @notice The Dynamic VOLT Rate Model exposes a pure function that
/// allows the DynamicVoltSystemOracle to set a dynamic VOLT rate based
/// on the current rate and percentage of liquid reserves. Lower liquid
/// reserves should increase the VOLT rate to incentivize new deposits
/// and improve the liquidity available for redemptions.
/// This model can we swapped out by governance, by deploying and new
/// model and pointing the DynamicVoltSystemOracle to the new model.
/// @author Eswak, Elliot Friedman
contract DynamicVoltRateModel {
    /// @notice the percentage at which the Volt rate will start going above
    /// the base rate. At less than 30% liquid reserves, rate jumps.
    uint256 public constant LIQUIDITY_JUMP_TARGET = 0.3e18; // 30%

    /// @notice maximum APR for the VOLT rate = 50%.
    uint256 public constant MAXIMUM_CHANGE_RATE = 0.5e18; // 50%

    /// @notice get the dynamic volt rate, based on current rate and percentage of
    /// liquid reserves. Expressed as an APR with 18 decimals.
    /// For instance, returning 0.5e18 would mean a 50% APR VOLT rate.
    /// @param baseRate the base VOLT rate, expressed as an APR with 18 decimals.
    /// @param liquidPercentage the percentage of PCV that is liquid, with 18 decimals.
    /// @return actualRate the actual rate of the system to set for the given
    /// liquidPercentage, expressed as an APR with 18 decimals.
    function getRate(uint256 baseRate, uint256 liquidPercentage)
        external
        pure
        returns (uint256 actualRate)
    {
        // if liquidity is fine, do not boost the current rate
        if (liquidPercentage > LIQUIDITY_JUMP_TARGET) {
            return baseRate;
        }
        // if current rate is already above maximum rate, do not boost the current rate
        // even if liquidity is low
        if (baseRate >= MAXIMUM_CHANGE_RATE) {
            return baseRate;
        }

        // Use linear interpolation to discover boost on top of base rate
        // Example figures :
        // - baseRate = 10%
        // - MAXIMUM_CHANGE_RATE = 50%
        //   => totalPossibleBoost = 50% - 10% = 40%
        // - liquidPercentage = 15%
        //   => jumpRateDelta = 30% - 15% = 15%
        //   => rateBoost = (15% * 40%) / 30% = 20%
        // this would boost the current rate from 10% APR to 30% APR.
        uint256 totalPossibleBoost = MAXIMUM_CHANGE_RATE - baseRate;
        uint256 jumpRateDelta = LIQUIDITY_JUMP_TARGET - liquidPercentage;
        uint256 rateBoost = (jumpRateDelta * totalPossibleBoost) /
            LIQUIDITY_JUMP_TARGET;

        actualRate = baseRate + rateBoost;
    }
}
