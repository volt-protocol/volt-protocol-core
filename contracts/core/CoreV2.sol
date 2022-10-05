// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Vcon} from "../vcon/Vcon.sol";
import {IVolt, Volt, IERC20} from "../volt/Volt.sol";
import {ICoreV2} from "./ICoreV2.sol";
import {PermissionsV2} from "./PermissionsV2.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// @title Source of truth for VOLT Protocol
/// @author Volt Protocol
/// @notice maintains roles, access control, Volt, Vcon, and the Vcon treasury
contract CoreV2 is ICoreV2, PermissionsV2 {
    /// @notice the address of the Volt contract
    IVolt public immutable override volt;

    /// @notice the address of the Vcon contract
    IERC20 public override vcon;

    /// @notice reference to the global reentrancy lock contract
    address public immutable globalReentrantLock;

    constructor(address _volt, address _globalReentrantLock) {
        volt = IVolt(_volt);

        /// msg.sender already has the VOLT Minting abilities, so grant them governor as well
        _setupRole(GOVERN_ROLE, msg.sender);

        globalReentrantLock = _globalReentrantLock;
    }

    /// @notice governor only function to set the VCON token
    function setVcon(IERC20 _vcon) external onlyGovernor {
        vcon = _vcon;

        emit VconUpdate(_vcon);
    }
}
