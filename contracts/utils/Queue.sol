// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Constants} from "./../Constants.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @notice contract to store a queue with 12 items
contract Queue {
    using SafeCast for *;

    /// @notice index 0 is the start of the queue
    /// index 11 is end of the queue
    /// this queue has a fixed length of 12 with each index representing a month
    /// index 0 = most recent month
    /// index 11 = furthest month in the past
    uint24[12] public queue;

    /// @param initialQueue this is the trailing twelve months of data
    constructor(uint24[] memory initialQueue) {
        require(initialQueue.length == 12, "Queue: invalid length");

        for (uint256 i = 0; i < initialQueue.length; i++) {
            queue[i] = initialQueue[i];
        }
    }

    /// @notice returns the sum of all elements in the queue
    function getQueueSum() public view returns (uint256 value) {
        /// this should never overflow
        unchecked {
            value += queue[0];
            value += queue[1];
            value += queue[2];
            value += queue[3];
            value += queue[4];
            value += queue[5];
            value += queue[6];
            value += queue[7];
            value += queue[8];
            value += queue[9];
            value += queue[10];
            value += queue[11];
        }
    }

    /// @notice get APR from queue by measuring (current month - 12 months ago) / 12 months ago
    /// @return percentageChange percentage change in basis points over past 12 months
    function getAPRFromQueue() public view returns (int256 percentageChange) {
        int256 delta = int24(queue[0]) - int24(queue[11]);
        percentageChange = delta * Constants.BASIS_POINTS_GRANULARITY_INT / int24(queue[11]);
    }

    /// @notice this is the only method needed as we will be using this queue to track CPI-U of the TTM
    /// add an element to the start of the queue and pop the last element off the queue
    /// @param elem the new element to add to the beginning of the queue
    function _unshift(uint24 elem) internal {
        queue[11] = queue[10];
        queue[10] = queue[9];
        queue[9] = queue[8];
        queue[8] = queue[7];
        queue[7] = queue[6];
        queue[6] = queue[5];
        queue[5] = queue[4];
        queue[4] = queue[3];
        queue[3] = queue[2];
        queue[2] = queue[1];
        queue[1] = queue[0];

        queue[0] = elem;
    }
}
