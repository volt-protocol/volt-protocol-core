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

contract RoleHierarchy is DSTest {
    using KArrayTree for KArrayTree.Node;

    KArrayTree.Node public roleHierarchy;
    mapping(bytes32 => address[]) public roleToAddress;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    constructor() {
        /// roles and their hierarchies are the same on both mainnet and arbitrum
        roleHierarchy.setRole(TribeRoles.GOVERNOR);
        roleHierarchy.insert(TribeRoles.GOVERNOR, TribeRoles.GUARDIAN);
        roleHierarchy.insert(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER);
        roleHierarchy.insert(TribeRoles.GOVERNOR, TribeRoles.MINTER);
        roleHierarchy.insert(TribeRoles.GOVERNOR, TribeRoles.PCV_GUARD_ADMIN);
        roleHierarchy.insert(TribeRoles.PCV_GUARD_ADMIN, TribeRoles.PCV_GUARD);
        roleHierarchy.insert(TribeRoles.GOVERNOR, TribeRoles.PSM_ADMIN_ROLE);
    }

    /// load tree to map
    function _loadTreeToMap(KArrayTree.Node storage root, Core core) internal {
        uint256 len = root.getCountImmediateChildren();
        if (len == 0) {
            /// end case for recursion
            return;
        }

        bytes32[] memory roles = root.getAllChildRoles();
        assert(len == roles.length); /// this statement should always be true
        for (uint256 i = 0; i < len; i++) {
            uint256 roleMemberCount = core.getRoleMemberCount(roles[i]);
            for (uint256 j = 0; j < roleMemberCount; j++) {
                /// add all members to the array
                roleToAddress[roles[i]].push(core.getRoleMember(roles[i], j));
            }
            _loadTreeToMap(root.childMap[root.childArray[i]], core);
        }
    }

    /// load up number of roles from Core and ensure that they match up with numbers here
    function _testGovernorRevokesSubordinates(address governor, Core core)
        internal
    {
        bytes32[] memory subordinateRoles = roleHierarchy.getAllChildRoles();

        vm.startPrank(governor);
        for (uint256 i = 0; i < subordinateRoles.length; i++) {
            address[] memory toRevoke = roleToAddress[subordinateRoles[i]];
            for (uint256 j = 0; j < toRevoke.length; j++) {
                address toRevokeRole = toRevoke[j];
                if (toRevokeRole != address(0)) {
                    core.revokeRole(subordinateRoles[i], toRevokeRole);
                    assertTrue(
                        !core.hasRole(subordinateRoles[i], toRevokeRole)
                    );
                } else {
                    /// if no address has the role, create and grant it
                    core.createRole(subordinateRoles[i], TribeRoles.GOVERNOR);
                    core.grantRole(subordinateRoles[i], toRevokeRole);
                    assertTrue(core.hasRole(subordinateRoles[i], toRevokeRole));
                    core.revokeRole(subordinateRoles[i], toRevokeRole);
                    assertTrue(
                        !core.hasRole(subordinateRoles[i], toRevokeRole)
                    );
                }
            }
        }
        vm.stopPrank();
    }

    function _revokeSubordinates(KArrayTree.Node storage root, Core core)
        internal
    {
        bytes32[] memory subordinateRoles = root.getAllChildRoles();
        if (subordinateRoles.length == 0) {
            return;
        }

        for (uint256 i = 0; i < subordinateRoles.length; i++) {
            address[] memory toRevoke = roleToAddress[subordinateRoles[i]];
            for (uint256 j = 0; j < toRevoke.length; j++) {
                if (toRevoke[j] != address(0)) {
                    _revokeSubordinates(
                        root.childMap[root.childArray[i]],
                        core
                    ); /// DFS delete all children, then delete parents
                    vm.prank(roleToAddress[root.getRole()][0]);
                    core.revokeRole(subordinateRoles[i], toRevoke[j]);
                    assertTrue(!core.hasRole(subordinateRoles[i], toRevoke[j]));
                }
            }
        }
    }

    /// @notice helper function to revoke and then test that all subordinates have been revoked
    /// @param root start of the tree
    /// @param core contract to reference for role member counts
    function _testAllSubordinatesRevoked(
        KArrayTree.Node storage root,
        Core core
    ) internal {
        uint256 len = root.getCountImmediateChildren();
        if (len == 0) {
            /// end case for recursion
            return;
        }

        bytes32[] memory roles = root.getAllChildRoles();
        assert(len == roles.length); /// this statement should always be true
        for (uint256 i = 0; i < len; i++) {
            uint256 roleMemberCount = core.getRoleMemberCount(roles[i]);
            require(roleMemberCount == 0, "All subordinate roles not revoked");
            _testAllSubordinatesRevoked(
                root.childMap[root.childArray[i]],
                core
            );
        }
    }
}
