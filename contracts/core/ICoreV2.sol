// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {IPermissionsV2} from "./IPermissionsV2.sol";
import {IVolt, IERC20} from "../volt/IVolt.sol";

/// @title Core Interface
/// @author (s) Volt and Fei Protocol
interface ICoreV2 is IPermissionsV2 {
    // ----------- Events -----------
    event VoltUpdate(IERC20 indexed _volt);
    event VconUpdate(IERC20 indexed _vcon);

    // ----------- Getters -----------

    /// @notice returns reference to the VOLT token contract
    function volt() external view returns (IVolt);

    /// @notice returns reference to the VCON token contract
    function vcon() external view returns (IERC20);

    /// @notice returns reference to the global reentrancy lock contract
    function globalReentrantLock() external view returns (address);
}
