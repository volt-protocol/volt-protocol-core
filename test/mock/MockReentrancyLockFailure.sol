// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {CoreRefV2} from "@voltprotocol/refs/CoreRefV2.sol";
import {MockReentrancyLock} from "@test/mock/MockReentrancyLock.sol";
import {IGlobalReentrancyLock} from "@voltprotocol/core/IGlobalReentrancyLock.sol";

contract MockReentrancyLockFailure is CoreRefV2 {
    using SafeCast for *;

    uint32 public lastBlockNumber;
    MockReentrancyLock public lock;

    constructor(address core, address _lock) CoreRefV2(core) {
        lock = MockReentrancyLock(_lock);
    }

    /// this will always fail due to the global reentrancy lock
    function globalReentrancyFails() external globalLock(1) {
        lock.testGlobalLock();
    }
}
