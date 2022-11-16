// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title Permissions interface
/// @author Volt Protocol
interface IPermissionsV2 is IAccessControl {
    // ----------- Governor only state changing api -----------

    function createRole(bytes32 role, bytes32 adminRole) external;

    function grantMinter(address minter) external;

    function grantPCVController(address pcvController) external;

    function grantGovernor(address governor) external;

    function grantGuardian(address guardian) external;

    function grantLocker(address levelOneLocker) external;

    function grantPCVGuard(address pcvGuard) external;

    function grantRateLimitedMinter(address rateLimitedMinter) external;

    function grantRateLimitedRedeemer(address rateLimitedRedeemer) external;

    function revokeMinter(address minter) external;

    function revokePCVController(address pcvController) external;

    function revokeGovernor(address governor) external;

    function revokeGuardian(address guardian) external;

    function revokeLocker(address levelOneLocker) external;

    function revokePCVGuard(address pcvGuard) external;

    function revokeRateLimitedMinter(address rateLimitedMinter) external;

    function revokeRateLimitedRedeemer(address rateLimitedRedeemer) external;

    // ----------- Revoker only state changing api -----------

    function revokeOverride(bytes32 role, address account) external;

    // ----------- Getters -----------

    function isMinter(address _address) external view returns (bool);

    function isGovernor(address _address) external view returns (bool);

    function isGuardian(address _address) external view returns (bool);

    function isPCVController(address _address) external view returns (bool);

    function isLocker(address _address) external view returns (bool);

    function isPCVGuard(address _address) external view returns (bool);

    function isRateLimitedMinter(address _address) external view returns (bool);

    function isRateLimitedRedeemer(
        address _address
    ) external view returns (bool);

    // ----------- Predefined Roles -----------

    /// @notice guardian is able to pause and unpause smart contracts
    /// and revoke non governor roles
    function GUARDIAN_ROLE() external view returns (bytes32);

    /// @notice governor role is the highest power in the system.
    /// it is able to pause and unpause smart contracts,
    /// grant any role to any address, create and then grant new roles,
    /// and revoke roles
    function GOVERN_ROLE() external view returns (bytes32);

    /// @notice minter role is allowed to mint Volt tokens
    function MINTER_ROLE() external view returns (bytes32);

    /// @notice pcv controller role controls PCV in the system
    /// and can arbitrarily move funds between deposits and addresses
    function PCV_CONTROLLER_ROLE() external view returns (bytes32);

    /// @notice global locker role can lock and unlock the global reentrancy
    /// lock. this allows for a system wide reentrancy lock.
    function LOCKER_ROLE() external view returns (bytes32);

    /// @notice granted to peg stability modules that will call in to deplete buffer
    /// and mint Volt
    function VOLT_RATE_LIMITED_MINTER_ROLE() external view returns (bytes32);

    /// @notice granted to peg stability modules that will call in to replenish the
    /// buffer Volt is minted from
    function VOLT_RATE_LIMITED_REDEEMER_ROLE() external view returns (bytes32);
}
