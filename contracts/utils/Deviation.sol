// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Constants} from "./../Constants.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title contract that determines whether or not a new value is within
/// an acceptable deviation threshold
/// @author Elliot Friedman, FEI Protocol
contract Deviation {
    using SafeCast for *;

    /// @notice event that is emitted when the threshold is changed
    event DeviationThresholdUpdate(uint256 oldThreshold, uint256 newThreshold);

    /// @notice the maximum update size relative to current, measured in basis points (1/10000)
    uint256 public immutable maxDeviationThresholdBasisPoints;

    constructor(uint256 _maxDeviationThresholdBasisPoints) {
        maxDeviationThresholdBasisPoints = _maxDeviationThresholdBasisPoints;
    }

    /// @notice return the percent deviation between a and b in basis points terms
    function calculateDeviationThresholdBasisPoints(int256 a, int256 b)
        public
        pure
        returns (uint256)
    {
        int256 delta = (a < b) ? (b - a) : (a - b);

        return
            (uint256(delta) * Constants.BASIS_POINTS_GRANULARITY) /
            (a < 0 ? a * -1 : a).toUint256();
    }

    /// @notice function to return whether or not the new price is within
    /// the acceptable deviation threshold
    function isWithinDeviationThreshold(int256 oldValue, int256 newValue)
        public
        view
        returns (bool)
    {
        return
            maxDeviationThresholdBasisPoints >=
            calculateDeviationThresholdBasisPoints(oldValue, newValue);
    }
}
