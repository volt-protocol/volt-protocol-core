// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {IGlobalReentrancyLock} from "../core/IGlobalReentrancyLock.sol";

contract MockReentrancyLock is CoreRefV2 {
    using SafeCast for *;

    uint32 public lastBlockNumber;

    constructor(address core) CoreRefV2(core) {}

    /// this contract asserts the core invariant of global reentrancy lock
    /// that it is always locked during execution
    function testGlobalLock() external globalLock(1) {
        require(
            core().globalReentrancyLock().isLocked(),
            "System not locked correctly"
        );
        lastBlockNumber = block.number.toUint32();
    }

    /// this will always fail due to the global reentrancy lock
    function globalLockReentrantFailure() external globalLock(1) {
        MockReentrancyLock(address(this)).testGlobalLock();
    }
}
