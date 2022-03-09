// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Constants} from "./../Constants.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @notice contract to store a queue with 12 items
contract Queue {
    using SafeCast for *;

    /// @notice index 0 is the start of the queue, index 1 is the end
    /// using uint128 so that the queue only takes one storage slot
    uint128[2] public queue;

    /// @param initialQueue this is the trailing twelve months of data
    constructor(uint128[] memory initialQueue) {
        require(initialQueue.length == 2, "Queue: invalid length");

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
        }
    }

    /// @notice get APR from queue by measuring (current month - 12 months ago) / 12 months ago
    /// @return percentageChange percentage change in basis points over past 12 months
    function getAPRFromQueue() public view returns (int256 percentageChange) {
        int256 delta = int128(queue[0]) - int128(queue[1]);
        percentageChange =
            (delta * Constants.BASIS_POINTS_GRANULARITY_INT) /
            int128(queue[1]);
    }

    /// @notice this is the only method needed as we will be using this queue to track CPI-U of the TTM
    /// add an element to the start of the queue and pop the last element off the queue
    /// @param elem the new element to add to the beginning of the queue
    function _unshift(uint128 elem) internal {
        queue[1] = queue[0];

        queue[0] = elem;
    }
}
