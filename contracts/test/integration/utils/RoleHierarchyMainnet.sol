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
import {RoleHierarchy} from "./RoleHierarchy.sol";

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
