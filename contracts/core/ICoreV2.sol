// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IVolt, IERC20} from "../volt/IVolt.sol";
import {IPermissionsV2} from "./IPermissionsV2.sol";

/// @title Core Interface
/// @author (s) Volt and Fei Protocol
interface ICoreV2 is IPermissionsV2 {
    // ----------- Events -----------

    /// @notice emitted with reference to VOLT token is updated
    event VoltUpdate(address indexed oldVolt, address indexed newVolt);

    /// @notice emitted when reference to VCON token is updated
    event VconUpdate(address indexed oldVcon, address indexed newVcon);

    // ----------- Getters -----------

    /// @notice returns reference to the VOLT token contract
    function volt() external view returns (IVolt);

    /// @notice returns reference to the VCON token contract
    function vcon() external view returns (IERC20);
}
