// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./ScalingPriceOracle.sol";
import "contracts/utils/Deviation.sol";
import "contracts/refs/CoreRef.sol";

/// @author Elliot Friedman
contract GovernableScalingPriceOracle is ScalingPriceOracle, Deviation, CoreRef {

    constructor(
        uint256 _duration,
        int256 _annualChangeRateBasisPoints,
        uint256 _maxDeviationThresholdBasisPoints,
        address coreAddress
    )
        ScalingPriceOracle(_duration, _annualChangeRateBasisPoints)
        Deviation(_maxDeviationThresholdBasisPoints)
        CoreRef(coreAddress)
    {}

    /// @notice function for priviledged roles to be able to upgrade the system
    function updateOracleChangeRate(int256 _newChangeRateBasisPoints) external onlyGovernorOrGuardianOrAdmin {
        require(
            isWithinDeviationThreshold(annualChangeRateBasisPoints, _newChangeRateBasisPoints),
            "GovernableScalingPriceOracle: new change rate is outside of allowable deviation"
        );

        _updateOraclePrice();
        annualChangeRateBasisPoints = _newChangeRateBasisPoints;
    }

    function compoundInterest() external onlyGovernorOrGuardianOrAdmin {
        _updateOraclePrice();
    }
}
