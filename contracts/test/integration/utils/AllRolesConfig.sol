pragma solidity =0.8.13;

import {VoltRoles} from "contracts/core/VoltRoles.sol";

contract AllRolesConfig {
    /// @notice all roles
    bytes32[5] public allRoles = [
        // cannot use VoltRoles.GOVERNOR, because hashed string
        // changed in V2 from GOVERN_ROLE to GOVERNOR_ROLE.
        // When V2 goes live, this integration test will need
        // updating, and we'll be able to use VoltRoles.GOVERNOR
        keccak256("GOVERN_ROLE"),
        VoltRoles.GUARDIAN,
        VoltRoles.PCV_CONTROLLER,
        VoltRoles.MINTER,
        VoltRoles.PCV_GUARD
    ];

    /// how many of each role exists
    uint256[] public numEachRole;

    /// @notice array of arrays that has all addresses in each role
    address[][5] public allAddresses;

    /// ------ @notice number of each role in the system ------

    /// new timelock, multisig, core
    uint256 public constant numGovernors = 3;

    /// PCV Guardian
    uint256 public constant numGuardians = 1;

    /// multisig, PCV Guardian, ERC20Allocator, COMPOUND_PCV_ROUTER
    uint256 public constant numPCVControllers = 4;

    /// Global Rate Limited Minter
    uint256 public constant numMinters = 0;

    /// EOA1, EOA2 & EOA3
    uint256 public constant numPCVGuards = 3;

    /// @notice all the number of each roles in order of the allRoles array
    uint256[5] public roleCounts = [
        numGovernors,
        numGuardians,
        numPCVControllers,
        numMinters,
        numPCVGuards
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
