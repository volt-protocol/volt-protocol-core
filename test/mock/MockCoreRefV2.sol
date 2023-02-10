// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {CoreRefV2} from "@voltprotocol/refs/CoreRefV2.sol";
import {VoltRoles} from "@voltprotocol/core/VoltRoles.sol";

contract MockCoreRefV2 is CoreRefV2 {
    constructor(address core) CoreRefV2(core) {}

    function testMinter() public onlyMinter {}

    function testPCVController() public onlyPCVController {}

    function testGovernor() public onlyGovernor {}

    function testGuardian() public onlyGuardianOrGovernor {}

    function testSystemState() public onlyVoltRole(VoltRoles.LOCKER) {}

    function testSystemLocksToLevel1() public globalLock(1) {}

    function testSystemLocksToLevel2() public globalLock(2) {}

    /// invalid lock level, doesn't matter because the lock is disabled in test
    function testSystemLocksToLevel3() public globalLock(3) {}

    function testSystemLockLevel1() public isGlobalReentrancyLocked(1) {}

    function testSystemLockLevel2() public isGlobalReentrancyLocked(2) {}

    function testStateGovernorMinter()
        public
        hasAnyOfThreeRoles(
            VoltRoles.LOCKER,
            VoltRoles.GOVERNOR,
            VoltRoles.MINTER
        )
    {}
}
