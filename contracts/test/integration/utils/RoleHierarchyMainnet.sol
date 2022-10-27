// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Vm} from "./../../unit/utils/Vm.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {VoltRoles} from "../../../core/VoltRoles.sol";
import {KArrayTree} from "./KArrayTree.sol";
import {RoleTesting} from "./RoleTesting.sol";
import {RoleHierarchy} from "./RoleHierarchy.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {Core, Vcon, Volt, IERC20, IVolt} from "../../../core/Core.sol";

contract RoleHierarchyMainnetIntegrationTest is RoleHierarchy {
    using KArrayTree for KArrayTree.Node;

    Core private core = Core(MainnetAddresses.CORE);

    function setUp() public {
        _loadTreeToMap(roleHierarchy, core);
        roleToAddress[roleHierarchy.getRole()].push(MainnetAddresses.GOVERNOR); /// must set governor address manually
    }

    function testGovernorRevokesSubordinates() public {
        _testGovernorRevokesSubordinates(MainnetAddresses.GOVERNOR, core);
    }

    function testRevokeAllSubordinates() public {
        _revokeSubordinates(roleHierarchy, core); /// revoke all subordinates
        _testAllSubordinatesRevoked(roleHierarchy, core); /// test that all subordinates no longer have their roles
    }
}
