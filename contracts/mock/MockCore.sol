// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./../core/Permissions.sol";
import "../vcon/Vcon.sol";
import "../volt/Volt.sol";

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// @title Mock Source of truth for Fei Protocol
/// @author Fei Protocol
/// @notice maintains roles, access control, fei, tribe, genesisGroup, and the TRIBE treasury
contract MockCore is Permissions, Initializable {

    /// @notice the address of the FEI contract
    IVolt public volt;
    
    /// @notice the address of the TRIBE contract
    IERC20 public vcon;

    function init() external initializer {
        _setupGovernor(msg.sender);

        Volt _volt = new Volt(address(this));
        volt = IVolt(_volt);

        Vcon _vcon = new Vcon(address(this), msg.sender);
        vcon = IERC20(address(_vcon));
    }

    fallback(bytes calldata) external returns (bytes memory) {
        return bytes("0x01");
    }
}
