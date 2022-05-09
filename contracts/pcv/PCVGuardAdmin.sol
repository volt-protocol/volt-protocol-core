// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {IPCVGuardAdmin} from "./IPCVGuardAdmin.sol";
import {CoreRef} from "../refs/CoreRef.sol";
import {TribeRoles} from "../core/TribeRoles.sol";
import {ICore} from "../core/ICore.sol";

/// @title PCV Guard Admin
/// @author Volt Protocol
/// @notice This contract interfaces between access controls and the PCV Guardian
/// allowing for multiple roles to manage the PCV Guard role, as access controls only allow for
/// a single admin for each role
contract PCVGuardAdmin is IPCVGuardAdmin, CoreRef {
    ICore private immutable _core;

    constructor(address coreAddress) CoreRef(coreAddress) {
        _core = ICore(coreAddress);
    }

    // ---------- Governor-Only State-Changing API ----------
    function grantPCVGuardRole(address newGuard)
        external
        override
        onlyGovernor
    {
        _core.grantRole(TribeRoles.PCV_GUARD, newGuard);
    }

    // ---------- Governor-Or-Guardian-Only State-Changing API ----------

    function revokePCVGuardRole(address oldGuard)
        external
        override
        onlyGuardianOrGovernor
    {
        _core.revokeRole(TribeRoles.PCV_GUARD, oldGuard);
    }
}
