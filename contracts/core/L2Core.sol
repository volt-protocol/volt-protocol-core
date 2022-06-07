// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Vcon} from "../vcon/Vcon.sol";
import {IVolt, Volt, IERC20} from "../volt/Volt.sol";
import {ICore} from "./ICore.sol";
import {Permissions} from "./Permissions.sol";

/// @title Source of truth for VOLT Protocol on L2
/// @author Volt Protocol
/// @notice maintains roles, access control, Volt, Vcon, and the Vcon treasury
contract L2Core is ICore, Permissions {
    /// @notice the address of the VOLT contract
    IVolt public immutable override volt;

    /// @notice the address of the Vcon contract
    IERC20 public override vcon;

    constructor(IVolt _volt) {
        volt = _volt;
        /// give msg.sender the governor role
        _setupGovernor(msg.sender);
    }

    /// @notice governor only function to set the VCON token
    function setVcon(IERC20 _vcon) external onlyGovernor {
        vcon = _vcon;

        emit VconUpdate(_vcon);
    }
}
