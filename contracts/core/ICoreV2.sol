// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {IVolt, IERC20} from "../volt/IVolt.sol";
import {IPermissionsV2} from "./IPermissionsV2.sol";
import {IGlobalReentrancyLock} from "./IGlobalReentrancyLock.sol";

/// @title Core Interface
/// @author (s) Volt and Fei Protocol
interface ICoreV2 is IPermissionsV2, IGlobalReentrancyLock {
    // ----------- Events -----------

    /// @notice emitted with new reference to the VOLT token
    event VoltUpdate(address indexed _volt);

    /// @notice emitted with new reference to the VCON token
    event VconUpdate(address indexed _vcon);

    // ----------- Getters -----------

    /// @notice returns reference to the VOLT token contract
    function volt() external view returns (IVolt);

    /// @notice returns reference to the VCON token contract
    function vcon() external view returns (IERC20);
}
