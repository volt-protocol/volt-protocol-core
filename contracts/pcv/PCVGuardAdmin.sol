// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IPCVGuardAdmin} from "./IPCVGuardAdmin.sol";
import {CoreRef} from "../refs/CoreRef.sol";
import {TribeRoles} from "../core/TribeRoles.sol";
import {ICore} from "../core/ICore.sol";

/// @title PCV Guard Admin
/// @author Volt Protocol
/// @notice This contract interfaces between access controls and the PCV Guard
/// allowing for multiple roles to manage the PCV Guard role, as access controls only allow for
/// a single admin for each role
contract PCVGuardAdmin is IPCVGuardAdmin, CoreRef {
    constructor(address _core) CoreRef(_core) {}

    // ---------- Governor-Only State-Changing API ----------

    /// @notice This function can only be called by the Governor role to grant the PCV Guard role
    /// @param newGuard address of the account to be made a PCV Guard
    function grantPCVGuardRole(address newGuard)
        external
        override
        onlyGovernor
    {
        core().grantRole(TribeRoles.PCV_GUARD, newGuard);
    }

    // ---------- Governor-Or-Guardian-Only State-Changing API ----------

    /// @notice This function can only be called by the Governor or Guardian roles to revoke the PCV Guard role
    /// @param oldGuard address of the account to be revoked the role of PCV Guard
    function revokePCVGuardRole(address oldGuard)
        external
        override
        onlyGuardianOrGovernor
    {
        core().revokeRole(TribeRoles.PCV_GUARD, oldGuard);
    }
}
