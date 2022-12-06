// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {Vm} from "./../../unit/utils/Vm.sol";
import {Core} from "../../../core/Core.sol";
import {DSTest} from "./../../unit/utils/DSTest.sol";
import {VoltRoles} from "../../../core/VoltRoles.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {Core, Vcon, Volt, IERC20, IVolt} from "../../../core/Core.sol";

contract RoleTesting is DSTest {
    /// @notice map role to the string name
    mapping(bytes32 => string) roleToName;

    constructor() {
        roleToName[VoltRoles.GOVERN] = "GOVERNOR";
        roleToName[VoltRoles.PCV_CONTROLLER] = "PCV_CONTROLLER";
        roleToName[VoltRoles.GUARDIAN] = "GUARDIAN";
        roleToName[VoltRoles.MINTER] = "MINTER";
        roleToName[VoltRoles.PCV_GUARD] = "PCV_GUARD";
    }

    /// load up number of roles from Core and ensure that they match up with numbers here
    function _testRoleArity(
        bytes32[] memory allRoles,
        uint256[5] memory roleCounts,
        uint256[] memory numEachRole
    ) internal view {
        for (uint256 i = 0; i < allRoles.length; i++) {
            if (i == 2 && block.chainid == 42161) {
                numEachRole[i] = 4;
            } // patch for difference in PCV controller roles on arbitrum & mainnet
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
        address[][5] memory allAddresses,
        Core core
    ) internal {
        for (uint256 i = 0; i < allRoles.length; i++) {
            for (uint256 j = 0; j < allAddresses[i].length; j++) {
                if (i == 2 && j == 2 && block.chainid == 42161) {
                    continue; // patch for difference in PCV controller roles on arbitrum & mainnet
                }
                assertTrue(core.hasRole(allRoles[i], allAddresses[i][j]));
            }
        }
    }
}
