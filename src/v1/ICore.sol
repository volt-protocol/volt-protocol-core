// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IPermissions} from "@voltprotocol/v1/IPermissions.sol";
import {IVolt, IERC20} from "@voltprotocol/volt/IVolt.sol";

/// @title Core Interface
/// @author Fei Protocol
interface ICore is IPermissions {
    // ----------- Events -----------
    event VoltUpdate(IERC20 indexed _volt);
    event VconUpdate(IERC20 indexed _vcon);

    // ----------- Getters -----------

    function volt() external view returns (IVolt);

    function vcon() external view returns (IERC20);
}
