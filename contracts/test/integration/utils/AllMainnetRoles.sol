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

import {console} from "hardhat/console.sol";

contract AllMainnetRoles {
    /// @notice all roles
    bytes32[] private allRoles;
    /// how many of each role exists
    uint256[] private numEachRole;

    Core private core = Core(MainnetAddresses.CORE);

    /// @notice array of arrays that has all addresses in each role
    address[9][] private allAddresses;

    /// ------ @notice number of each role in the system ------

    /// timelock, multisig, core
    uint256 public constant numGovernors = 2;

    /// EOA1, multisig, pcv guardian
    uint256 public constant numGuardians = 3;

    /// NonCustodial PSM, multisig, PCV Guardian
    uint256 public constant numPCVControllers = 3;

    /// Global Rate Limited Minter
    /// TODO deprecate the global rate limited minter
    uint256 public constant numMinters = 1;

    /// Revoked EOA 1, EOA2
    uint256 public constant numPCVGuards = 2;

    /// NA
    uint256 public constant numParamAdmins = 0;

    /// NA
    uint256 public constant numPCVGuardianAdmins = 0;

    /// PCV Guard Admin
    uint256 public constant numPCVGuardAdmins = 1;

    /// NA
    uint256 public constant numAddMinters = 0;

    /// NA
    uint256 public constant numPSMAdmins = 0;

    /// @notice all the number of each roles in order of the allRoles array
    uint256[10] private roleCounts = [
        numGovernors,
        numGuardians,
        numPCVControllers,
        numMinters,
        numPCVGuards,
        numParamAdmins,
        numPCVGuardianAdmins,
        numPCVGuardAdmins,
        numAddMinters,
        numPSMAdmins
    ];

    function setup() public {
        allRoles.push(TribeRoles.GOVERNOR);
        allRoles.push(TribeRoles.GUARDIAN);
        allRoles.push(TribeRoles.PCV_CONTROLLER);
        allRoles.push(TribeRoles.MINTER);
        allRoles.push(TribeRoles.PCV_GUARD);
        allRoles.push(TribeRoles.PARAMETER_ADMIN);
        allRoles.push(TribeRoles.PCV_GUARDIAN_ADMIN);
        allRoles.push(TribeRoles.PCV_GUARD_ADMIN);
        allRoles.push(TribeRoles.ADD_MINTER_ROLE);
        allRoles.push(TribeRoles.PSM_ADMIN_ROLE);

        for (uint256 i = 0; i < allRoles.length; i++) {
            numEachRole.push(core.getRoleMemberCount(allRoles[i]));
        }

        /// sanity check
        assert(numEachRole.length == allRoles.length);
    }

    /// load up number of roles from Core and ensure that they match up with numbers here
    function testRoleArity() public view {
        for (uint256 i = 0; i < allRoles.length; i++) {
            if (numEachRole[i] != roleCounts[i]) {
                revert(
                    string(
                        abi.encodePacked(
                            "Arity mismatch for role ",
                            Strings.toHexString(uint256(allRoles[i]), 32),
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
}
