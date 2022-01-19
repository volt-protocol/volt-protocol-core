// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./Permissions.sol";
import "./ICore.sol";
import "../volt/Volt.sol";
import "../vcon/Vcon.sol";

/// @title Source of truth for Fei Protocol
/// @author Fei Protocol
/// @notice maintains roles, access control, Volt, Vcon, and the Vcon treasury
contract Core is ICore, Permissions, Initializable {

    /// @notice the address of the FEI contract
    IVolt public override volt;
    
    /// @notice the address of the Vcon contract
    IERC20 public override vcon;

    function init() external override initializer {
        _setupGovernor(msg.sender);
        
        Volt _volt = new Volt(address(this));
        _setVolt(address(_volt));

        Vcon _vcon = new Vcon(address(this), msg.sender);
        _setVcon(address(_vcon));
    }

    /// @notice sets Volt address to a new address
    /// @param token new Volt address
    function setVolt(address token) external override onlyGovernor {
        _setVolt(token);
    }

    /// @notice sets Vcon address to a new address
    /// @param token new Vcon address
    function setVcon(address token) external override onlyGovernor {
        _setVcon(token);
    }

    function _setVolt(address token) internal {
        volt = IVolt(token);
        emit VoltUpdate(token);
    }

    function _setVcon(address token) internal {
        vcon = IERC20(token);
        emit VconUpdate(token);
    }
}
