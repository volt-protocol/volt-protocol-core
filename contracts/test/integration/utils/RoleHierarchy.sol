// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Core, Vcon, Volt, IERC20, IVolt} from "../../../core/Core.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {TribeRoles} from "../../../core/TribeRoles.sol";
import {DSTest} from "./../../unit/utils/DSTest.sol";
import {L2Core} from "../../../core/L2Core.sol";
import {Core} from "../../../core/Core.sol";
import {Vm} from "./../../unit/utils/Vm.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {RoleTesting} from "./RoleTesting.sol";
import {KArrayTree} from "./KArrayTree.sol";

contract RoleHierarchyMainnetIntegrationTest is RoleTesting {
    using KArrayTree for KArrayTree.Node;

    KArrayTree.Node public roleHierarchy;
    mapping(bytes32 => address) roleToAddress;
    Vm public constant vm = Vm(HEVM_ADDRESS);
    Core private core = Core(MainnetAddresses.CORE);

    function setUp() public {
        roleHierarchy.setRole(TribeRoles.GOVERNOR);
        roleHierarchy.insert(TribeRoles.GOVERNOR, TribeRoles.GUARDIAN);
        roleHierarchy.insert(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER);
        roleHierarchy.insert(TribeRoles.GOVERNOR, TribeRoles.MINTER);
        roleHierarchy.insert(TribeRoles.GOVERNOR, TribeRoles.PCV_GUARD_ADMIN);
        roleHierarchy.insert(TribeRoles.PCV_GUARD_ADMIN, TribeRoles.PCV_GUARD);

        roleHierarchy.insert(TribeRoles.GOVERNOR, TribeRoles.PARAMETER_ADMIN);
        roleHierarchy.insert(
            TribeRoles.GOVERNOR,
            TribeRoles.PCV_GUARDIAN_ADMIN
        );
        roleHierarchy.insert(TribeRoles.GOVERNOR, TribeRoles.ADD_MINTER_ROLE);
        roleHierarchy.insert(TribeRoles.GOVERNOR, TribeRoles.PSM_ADMIN_ROLE);

        roleToAddress[TribeRoles.GUARDIAN] = MainnetAddresses.GUARDIAN;
        roleToAddress[TribeRoles.MINTER] = MainnetAddresses.GRLM;
        roleToAddress[TribeRoles.PCV_GUARD_ADMIN] = MainnetAddresses
            .PCV_GUARD_ADMIN;
    }

    /// load up number of roles from Core and ensure that they match up with numbers here
    function testGovernorRevokesSubordinateRoles() public {
        bytes32[] memory subordinateRoles = roleHierarchy.getAllChildRoles();

        vm.startPrank(MainnetAddresses.GOVERNOR);
        for (uint256 i = 0; i < subordinateRoles.length; i++) {
            address toRevoke = roleToAddress[subordinateRoles[i]];
            if (toRevoke != address(0)) {
                core.revokeRole(subordinateRoles[i], toRevoke);
                assertTrue(!core.hasRole(subordinateRoles[i], toRevoke));
            }
        }
        vm.stopPrank();
    }

    /// assert that all addresses have the proper role
    function testRoleAddresses() public {}
}
