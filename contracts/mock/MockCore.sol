// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./../core/Permissions.sol";
import "../vcon/Vcon.sol";
import "../volt/Volt.sol";

/// @title Mock Source of truth for Fei Protocol
/// @author Fei Protocol
/// @notice maintains roles, access control, fei, tribe, genesisGroup, and the TRIBE treasury
contract MockCore is Permissions {

    /// @notice the address of the FEI contract
    IVolt public volt;
    
    /// @notice the address of the TRIBE contract
    IERC20 public vcon;

    /// @notice tracks whether the contract has been initialized
    bool private _initialized;

    constructor() {
        require(!_initialized, "initialized");
        _initialized = true;

        uint256 id;
        assembly {
            id := chainid()
        }
        require(id != 1, "cannot deploy mock on mainnet");
        _setupGovernor(msg.sender);
        
        Volt _volt = new Volt(address(this));
        volt = IVolt(_volt);

        Vcon _vcon = new Vcon(msg.sender, msg.sender);
        vcon = IERC20(address(_vcon));
    }
}
