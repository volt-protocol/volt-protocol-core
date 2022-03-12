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

    function init() external initializer {
        volt = new Volt(address(this));
        vcon = IERC20(address(new Vcon(msg.sender, msg.sender)));
        /// msg.sender already has all of the VCON + VCON Minting abilities, so grant them governor as well
        _setupGovernor(msg.sender);
    }
}
