// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVolt} from "../volt/IVolt.sol";
import {ICoreV2} from "../core/ICoreV2.sol";

/// @title CoreRef interface
/// @author Volt & Fei Protocol
interface ICoreRefV2 {
    // ----------- Events -----------

    event CoreUpdate(address indexed oldCore, address indexed newCore);

    event ContractAdminRoleUpdate(
        bytes32 indexed oldContractAdminRole,
        bytes32 indexed newContractAdminRole
    );

    // ----------- Governor or Guardian only state changing api -----------

    function pause() external;

    function unpause() external;

    // ----------- Getters -----------

    function core() external view returns (ICoreV2);

    function volt() external view returns (IVolt);

    function vcon() external view returns (IERC20);

    function voltBalance() external view returns (uint256);

    function vconBalance() external view returns (uint256);
}
