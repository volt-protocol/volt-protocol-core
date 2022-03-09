// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./../utils/Queue.sol";

contract MockQueue is Queue {
    constructor(uint128[] memory initialQueue) Queue(initialQueue) {}

    function unshift(uint128 elem) external returns (bool) {
        _unshift(elem);

        return true;
    }
}
