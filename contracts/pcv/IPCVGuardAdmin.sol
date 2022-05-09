// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

/// @title PCV GuardAdmin Interface
/// @author Volt Protocol
interface IPCVGuardAdmin {
    // Role Heirarchy
    // Governor admin of -> PCV_GUARD_ADMIN
    // PCV_GUARD_ADMIN admin of -> PCV_GUARD
    // This contract gets the PCV_GUARD_ADMIN role

    // ----------- Setters -----------

    // only governor
    function grantPCVGuardRole(address newGuard) external;

    // only governor or guardian
    function revokePCVGuardRole(address newGuard) external;
}
