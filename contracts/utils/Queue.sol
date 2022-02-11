// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./../Constants.sol";

import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @notice contract to store a queue 12 things long
contract Queue {

    using SafeCast for *;

    /// @notice index 0 is the start of the queue
    /// index 11 is end of the queue
    /// this queue has a fixed length of 12 with each index representing a month
    uint256[12] public queue;

    /// 0 = most recent month
    /// 11 = month furthest in the past

    constructor(uint256[] memory initialQueue) {
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


    function getAPRFromQueue() public view returns (int256) {
        int256 delta = int256(queue[0]) - int256(queue[11]);
        int256 percentageChange = int256(delta) * int256(Constants.BASIS_POINTS_GRANULARITY) / int256(queue[11]);

        return percentageChange;
    }

    /// @notice this is the only method needed as we will be using this queue to track CPI-U of the TTM
    /// add an element to the start of the queue and pop the last element off the queue
    /// @param elem the new element to add to the beginning of the queue
    function unshift(uint256 elem) internal {
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
