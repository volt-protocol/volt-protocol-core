pragma solidity =0.8.13;

contract MainnetRolesConfig {
    /// @notice all roles
    bytes32[] public allRoles;
    /// how many of each role exists
    uint256[] public numEachRole;

    /// @notice array of arrays that has all addresses in each role
    address[][7] public allAddresses;

    /// ------ @notice number of each role in the system ------

    /// new timelock, multisig, core
    uint256 public constant numGovernors = 3;

    /// PCV Guardian
    uint256 public constant numGuardians = 1;

    /// multisig, PCV Guardian
    uint256 public constant numPCVControllers = 2;

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
}
