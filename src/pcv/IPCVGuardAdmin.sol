// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

/// @title PCV GuardAdmin Interface
/// @author Volt Protocol
interface IPCVGuardAdmin {
    // Role Heirarchy
    // Governor admin of -> PCV_GUARD_ADMIN
    // PCV_GUARD_ADMIN admin of -> PCV_GUARD
    // This contract gets the PCV_GUARD_ADMIN role

    // ---------- Governor-Only State-Changing API ----------

    /// @notice This function can only be called by the Governor role to grant the PCV Guard role
    /// @param newGuard address of the account to be revoked the role of PCV Guard
    function grantPCVGuardRole(address newGuard) external;

    // ---------- Governor-Or-Guardian-Only State-Changing API ----------

    /// @notice This function can only be called by the Governor or Guardian roles to revoke the PCV Guard role
    /// @param oldGuard address of the account to be revoked the role of PCV Guard
    function revokePCVGuardRole(address oldGuard) external;
}
