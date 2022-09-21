// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Vcon} from "../vcon/Vcon.sol";
import {IVolt, Volt, IERC20} from "../volt/Volt.sol";
import {ICore} from "./ICore.sol";
import {Permissions} from "./Permissions.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// @title Source of truth for VOLT Protocol
/// @author Fei Protocol
/// @notice maintains roles, access control, Volt, Vcon, and the Vcon treasury
contract Core is ICore, Permissions, Initializable {
    /// @notice the address of the FEI contract
    IVolt public override volt;

    /// @notice the address of the Vcon contract
    IERC20 public override vcon;

    constructor() Permissions() {
        _setupGovernor(msg.sender);
    }

    /// @notice governor only function to set the VCON token
    function setVcon(IERC20 _vcon) external onlyGovernor {
        vcon = _vcon;

        emit VconUpdate(_vcon);
    }

    /// @notice governor only function to set the VOLT token
    function setVolt(IVolt _volt) external onlyGovernor {
        volt = _volt;

        emit VoltUpdate(IERC20(address(_volt)));
    }
}
