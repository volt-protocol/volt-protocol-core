// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Vcon} from "../vcon/Vcon.sol";
import {IVolt, Volt, IERC20} from "../volt/Volt.sol";
import {ICoreV2} from "./ICoreV2.sol";
import {PermissionsV2} from "./PermissionsV2.sol";
import {GlobalReentrancyLock} from "./GlobalReentrancyLock.sol";

/// @title Source of truth for VOLT Protocol
/// @author Volt Protocol
/// @notice maintains roles, access control, Volt, Vcon, and the Vcon treasury
contract CoreV2 is ICoreV2, GlobalReentrancyLock {
    /// @notice address of the Volt token
    IVolt public override volt;

    /// @notice address of the Vcon token
    IERC20 public override vcon;

    /// @notice construct CoreV2
    /// @param _volt reference to the volt token
    constructor(address _volt) GlobalReentrancyLock() {
        volt = IVolt(_volt);

        /// msg.sender already has the VOLT Minting abilities, so grant them governor as well
        _setupRole(GOVERN_ROLE, msg.sender);
    }

    /// @notice governor only function to set the VCON token
    function setVcon(IERC20 _vcon) external onlyGovernor {
        vcon = _vcon;

        emit VconUpdate(address(_vcon));
    }

    /// @notice governor only function to set the VCON token
    function setVolt(IVolt _volt) external onlyGovernor {
        volt = _volt;

        emit VoltUpdate(address(_volt));
    }
}
