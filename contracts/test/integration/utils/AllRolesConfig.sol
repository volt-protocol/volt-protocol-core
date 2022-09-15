pragma solidity =0.8.13;

import {TribeRoles} from "contracts/core/TribeRoles.sol";

contract AllRolesConfig {
    /// @notice all roles
    bytes32[7] public allRoles = [
        TribeRoles.GOVERNOR,
        TribeRoles.GUARDIAN,
        TribeRoles.PCV_CONTROLLER,
        TribeRoles.MINTER,
        TribeRoles.PCV_GUARD,
        TribeRoles.PCV_GUARD_ADMIN,
        TribeRoles.PSM_ADMIN_ROLE
    ];

    /// how many of each role exists
    uint256[] public numEachRole;

    /// @notice array of arrays that has all addresses in each role
    address[][7] public allAddresses;

    /// ------ @notice number of each role in the system ------

    /// new timelock, multisig, core
    uint256 public constant numGovernors = 3;

    /// PCV Guardian
    uint256 public constant numGuardians = 1;

    /// multisig, PCV Guardian, ERC20Allocator
    uint256 public constant numPCVControllers = 3;

    /// Global Rate Limited Minter
    uint256 public constant numMinters = 0;

    /// EOA1, EOA2 & EOA3
    uint256 public constant numPCVGuards = 3;

    /// PCV Guard Admin
    uint256 public constant numPCVGuardAdmins = 1;

    /// NA
    uint256 public constant numPSMAdmins = 0;

    /// @notice all the number of each roles in order of the allRoles array
    uint256[7] public roleCounts = [
        numGovernors,
        numGuardians,
        numPCVControllers,
        numMinters,
        numPCVGuards,
        numPCVGuardAdmins,
        numPSMAdmins
    ];

    function getAllRoles() public view returns (bytes32[] memory) {
        uint256 roleLen = allRoles.length;
        bytes32[] memory allRolesArray = new bytes32[](roleLen);

        for (uint256 i = 0; i < roleLen; i++) {
            allRolesArray[i] = allRoles[i];
        }

        return allRolesArray;
    }
}
