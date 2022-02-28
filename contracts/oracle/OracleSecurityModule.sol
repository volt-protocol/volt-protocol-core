// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./../utils/Timed.sol";
import "./IScalingPriceOracle.sol";
import "./../refs/CoreRef.sol";
import "./../utils/Deviation.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract OracleSecurityModule is CoreRef, Timed, Deviation {
    using SafeCast for *;

    /// @notice last cached value
    uint256 public cachedValue;

    /// @notice the maximum amount an admin can change the cached value
    uint256 public maxAdminDeviation;

    /// @notice oracle to reference
    IScalingPriceOracle public immutable oracle;

    event CachedValueUpdate(uint256 oldValue, uint256 newValue);

    constructor(
        IScalingPriceOracle _oracle,
        address coreAddress,
        uint256 _duration,
        uint256 _maxDeviation,
        uint256 _maxAdminDeviation
    ) CoreRef(coreAddress) Timed(_duration) Deviation(_maxDeviation) {
        oracle = _oracle;
        cachedValue = oracle.getCurrentOraclePrice();
        maxAdminDeviation = _maxAdminDeviation;
        _initTimed();
    }

    /// @notice anyone is allowed to call this function and update the price based off of the scaling price oracle
    /// when it is not paused
    function updateCachedValue() external afterTimeInit whenNotPaused {
        uint256 newRecordedValue = oracle.getCurrentOraclePrice();
        uint256 oldRecordedValue = cachedValue;

        require(
            isWithinDeviationThreshold(oldRecordedValue.toInt256(), newRecordedValue.toInt256()),
            "OracleSecurityModule: deviation threshold exceeded"
        );

        cachedValue = newRecordedValue;

        emit CachedValueUpdate(oldRecordedValue, newRecordedValue);
    }

    function adminUpdateCachedValue(uint256 newRecordedValue) external afterTimeInit onlyGovernorOrGuardianOrAdmin {
        uint256 oldRecordedValue = cachedValue;

        require(
            maxAdminDeviation >= calculateDeviationThresholdBasisPoints(oldRecordedValue.toInt256(), newRecordedValue.toInt256()),
            "OracleSecurityModule: admin deviation threshold exceeded"
        );

        cachedValue = newRecordedValue;

        emit CachedValueUpdate(oldRecordedValue, newRecordedValue);
    }

    function updateDuration(uint256 newDuration) external onlyGovernor {
        _setDuration(newDuration);
    } 
}
