// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Constants} from "@voltprotocol/Constants.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title contract that determines whether or not a new value is within
/// an acceptable deviation threshold
/// @author Elliot Friedman
library DeviationWeiGranularity {
    using SafeCast for *;

    /// @notice return the percent deviation between a and b in wei. 1 eth = 100%
    function calculateDeviation(
        int256 a,
        int256 b
    ) internal pure returns (int256) {
        int256 delta = a - b;
        int256 basisPoints = (delta * Constants.ETH_GRANULARITY_INT) / a;

        return basisPoints;
    }
}
