// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Core} from "../../../core/Core.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {TribeRoles} from "../../../core/TribeRoles.sol";
import {DSTest} from "./../../unit/utils/DSTest.sol";
import {L2Core} from "../../../core/L2Core.sol";
import {Core} from "../../../core/Core.sol";
import {Vm} from "./../../unit/utils/Vm.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {RoleTesting} from "./RoleTesting.sol";
import {AllRolesConfig} from "./AllRolesConfig.sol";

contract IntegrationTestAllMainnetRoles is RoleTesting, AllRolesConfig {
    Core private core = Core(MainnetAddresses.CORE);

    function setUp() public {
        for (uint256 i = 0; i < allRoles.length; i++) {
            numEachRole.push(core.getRoleMemberCount(allRoles[i]));
        }

        allAddresses[0].push(MainnetAddresses.CORE);
        allAddresses[0].push(MainnetAddresses.GOVERNOR);
        allAddresses[0].push(MainnetAddresses.TIMELOCK_CONTROLLER);

        allAddresses[1].push(MainnetAddresses.PCV_GUARDIAN);

        allAddresses[2].push(MainnetAddresses.GOVERNOR);
        allAddresses[2].push(MainnetAddresses.PCV_GUARDIAN);

        allAddresses[4].push(MainnetAddresses.EOA_1);
        allAddresses[4].push(MainnetAddresses.EOA_2);
        allAddresses[4].push(MainnetAddresses.EOA_3);

        allAddresses[5].push(MainnetAddresses.PCV_GUARD_ADMIN);

        /// sanity check
        assert(numEachRole.length == allRoles.length);
    }

    /// load up number of roles from Core and ensure that they match up with numbers here
    function testRoleArity() public view {
        _testRoleArity(getAllRoles(), roleCounts, numEachRole);
    }

    /// assert that all addresses have the proper role
    function testRoleAddresses() public {
        _testRoleAddresses(getAllRoles(), allAddresses, core);
    }
}
