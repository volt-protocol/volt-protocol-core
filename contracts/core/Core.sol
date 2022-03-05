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

    /// @notice VOLT & VCON cannot be immutable as CoreRef in the VOLT contract
    /// cannot be constructed while Core is being constructed.

    /// @notice the address of the VOLT contract
    IVolt public override volt;
    
    /// @notice the address of the VCON contract
    IERC20 public override vcon;

    function init(address recipient) external override initializer {
        _setupGovernor(msg.sender);
        volt = new Volt(address(this));
        /// make the recipient the owner of all coins
        /// grant minting abilities to the timelock
        vcon = IERC20(address(new Vcon(recipient, msg.sender)));
    }
}
