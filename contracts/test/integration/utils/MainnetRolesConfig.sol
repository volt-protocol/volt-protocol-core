pragma solidity =0.8.13;

contract MainnetRolesConfig {
    /// @notice array of arrays that has all addresses in each role
    address[][7] public allAddresses;

    /// ------ @notice number of each role in the system ------

    /// timelock (currently deprecated), multisig, core
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
