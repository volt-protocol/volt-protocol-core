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

contract RoleTesting is DSTest {
    /// @notice map role to the string name
    mapping(bytes32 => string) roleToName;

    constructor() {
        roleToName[TribeRoles.GOVERNOR] = "GOVERNOR";
        roleToName[TribeRoles.PCV_CONTROLLER] = "PCV_CONTROLLER";
        roleToName[TribeRoles.GUARDIAN] = "GUARDIAN";
        roleToName[TribeRoles.MINTER] = "MINTER";
        roleToName[TribeRoles.PCV_GUARD] = "PCV_GUARD";
        roleToName[TribeRoles.PCV_GUARD_ADMIN] = "PCV_GUARD_ADMIN";
        roleToName[TribeRoles.PSM_ADMIN_ROLE] = "PSM_ADMIN_ROLE";
    }

    /// load up number of roles from Core and ensure that they match up with numbers here
    function _testRoleArity(
        bytes32[] memory allRoles,
        uint256[7] memory roleCounts,
        uint256[] memory numEachRole
    ) internal view {
        for (uint256 i = 0; i < allRoles.length; i++) {
            if (numEachRole[i] != roleCounts[i]) {
                revert(
                    string(
                        abi.encodePacked(
                            "Arity mismatch for role ",
                            roleToName[allRoles[i]],
                            " got: ",
                            Strings.toString(numEachRole[i]),
                            " expected: ",
                            Strings.toString(roleCounts[i]),
                            " index: ",
                            Strings.toString(i)
                        )
                    )
                );
            }
        }
    }

    /// assert that all addresses have the proper role
    function _testRoleAddresses(
        bytes32[] memory allRoles,
        address[][7] memory allAddresses,
        Core core
    ) internal {
        for (uint256 i = 0; i < allRoles.length; i++) {
            for (uint256 j = 0; j < allAddresses[i].length; j++) {
                assertTrue(core.hasRole(allRoles[i], allAddresses[i][j]));
            }
        }
    }
}
