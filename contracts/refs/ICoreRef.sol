// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICore} from "../core/ICore.sol";
import {IVolt} from "../volt/IVolt.sol";

/// @title CoreRef interface
/// @author (s) Fei Protocol, Volt Protocol
interface ICoreRef {
    // ----------- Events -----------

    event CoreUpdate(address indexed oldCore, address indexed newCore);

    // ----------- Governor or Guardian only state changing api -----------

    function pause() external;

    function unpause() external;

    function sweep(
        address token,
        address to,
        uint256 amount
    ) external;

    // ----------- Getters -----------

    function core() external view returns (ICore);

    function volt() external view returns (IVolt);

    function vcon() external view returns (IERC20);

    function voltBalance() external view returns (uint256);

    function vconBalance() external view returns (uint256);
}
