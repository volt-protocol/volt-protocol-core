// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

/// @title PCV GuardAdmin Interface
/// @author Volt Protocol
interface IPCVGuardAdmin {
    // Role Heirarchy
    // Governor admin of -> PCV_GUARD_ADMIN
    // PCV_GUARD_ADMIN admin of -> PCV_GUARD
    // This contract gets the PCV_GUARD_ADMIN role

    // ---------- Governor-Only State-Changing API ----------

    function grantPCVGuardRole(address newGuard) external;

    // ---------- Governor-Or-Guardian-Only State-Changing API ----------
    function revokePCVGuardRole(address newGuard) external;
}
