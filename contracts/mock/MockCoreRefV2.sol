// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {VoltRoles} from "./../core/VoltRoles.sol";

contract MockCoreRefV2 is CoreRefV2 {
    constructor(address core) CoreRefV2(core) {}

    function testMinter() public onlyMinter {}

    function testPCVController() public onlyPCVController {}

    function testGovernor() public onlyGovernor {}

    function testGuardian() public onlyGuardianOrGovernor {}

    function testSystemState()
        public
        onlyVoltRole(VoltRoles.SYSTEM_STATE_ROLE)
    {}

    function testStateGovernorMinter()
        public
        hasAnyOfThreeRoles(
            VoltRoles.SYSTEM_STATE_ROLE,
            VoltRoles.GOVERNOR,
            VoltRoles.MINTER
        )
    {}
}
