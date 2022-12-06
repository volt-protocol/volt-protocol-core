// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Core} from "../../../core/Core.sol";
import {ArbitrumAddresses} from "../fixtures/ArbitrumAddresses.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {VoltRoles} from "../../../core/VoltRoles.sol";
import {DSTest} from "./../../unit/utils/DSTest.sol";
import {Core} from "../../../core/Core.sol";
import {Vm} from "./../../unit/utils/Vm.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {RoleTesting} from "./RoleTesting.sol";
import {AllRolesConfig} from "./AllRolesConfig.sol";

contract ArbitrumTestAllArbitrumRoles is RoleTesting, AllRolesConfig {
    Core private core = Core(ArbitrumAddresses.CORE);

    function setUp() public {
        for (uint256 i = 0; i < allRoles.length; i++) {
            numEachRole.push(core.getRoleMemberCount(allRoles[i]));
        }

        /// Governors
        allAddresses[0].push(ArbitrumAddresses.CORE);
        allAddresses[0].push(ArbitrumAddresses.GOVERNOR);
        allAddresses[0].push(ArbitrumAddresses.TIMELOCK_CONTROLLER);

        /// Guardians
        allAddresses[1].push(ArbitrumAddresses.PCV_GUARDIAN);

        /// PCV Controllers
        allAddresses[2].push(ArbitrumAddresses.GOVERNOR);
        allAddresses[2].push(ArbitrumAddresses.PCV_GUARDIAN);
        allAddresses[2].push(ArbitrumAddresses.ERC20ALLOCATOR);

        /// PCV Guards
        allAddresses[4].push(ArbitrumAddresses.EOA_1);
        allAddresses[4].push(ArbitrumAddresses.EOA_2);
        allAddresses[4].push(ArbitrumAddresses.EOA_3);
        allAddresses[4].push(ArbitrumAddresses.EOA_4);

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
