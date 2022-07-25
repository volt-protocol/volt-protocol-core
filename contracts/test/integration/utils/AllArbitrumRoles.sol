// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Core} from "../../../core/Core.sol";
import {ArbitrumAddresses} from "../fixtures/ArbitrumAddresses.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {TribeRoles} from "../../../core/TribeRoles.sol";
import {DSTest} from "./../../unit/utils/DSTest.sol";
import {L2Core} from "../../../core/L2Core.sol";
import {Core} from "../../../core/Core.sol";
import {Vm} from "./../../unit/utils/Vm.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {RoleTesting} from "./RoleTesting.sol";
import {ArbitrumRolesConfig} from "./ArbitrumRolesConfig.sol";

contract ArbitrumTestAllArbitrumRoles is RoleTesting, ArbitrumRolesConfig {
    Core private core = Core(ArbitrumAddresses.CORE);

    function setUp() public {
        allRoles.push(TribeRoles.GOVERNOR);
        allRoles.push(TribeRoles.GUARDIAN);
        allRoles.push(TribeRoles.PCV_CONTROLLER);
        allRoles.push(TribeRoles.MINTER);
        allRoles.push(TribeRoles.PCV_GUARD);
        allRoles.push(TribeRoles.PCV_GUARD_ADMIN);
        allRoles.push(TribeRoles.PSM_ADMIN_ROLE);

        for (uint256 i = 0; i < allRoles.length; i++) {
            numEachRole.push(core.getRoleMemberCount(allRoles[i]));
        }

        allAddresses[0].push(ArbitrumAddresses.CORE);
        allAddresses[0].push(ArbitrumAddresses.GOVERNOR);

        allAddresses[1].push(ArbitrumAddresses.GUARDIAN);

        allAddresses[2].push(ArbitrumAddresses.GOVERNOR);
        allAddresses[2].push(ArbitrumAddresses.GUARDIAN);
        allAddresses[2].push(ArbitrumAddresses.DEPRECATED_TIMELOCK);

        allAddresses[4].push(MainnetAddresses.REVOKED_EOA_1);
        allAddresses[4].push(MainnetAddresses.EOA_2);

        allAddresses[5].push(ArbitrumAddresses.PCV_GUARD_ADMIN);

        /// sanity check
        assert(numEachRole.length == allRoles.length);
    }

    /// load up number of roles from Core and ensure that they match up with numbers here
    function testRoleArity() public view {
        _testRoleArity(allRoles, roleCounts, numEachRole);
    }

    /// assert that all addresses have the proper role
    function testRoleAddresses() public {
        _testRoleAddresses(allRoles, allAddresses, core);
    }
}
