// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IGRLM} from "../minter/IGRLM.sol";
import {ICoreV2} from "../core/ICoreV2.sol";
import {IPCVOracle} from "../oracle/IPCVOracle.sol";
import {IVolt, IVoltBurn} from "../volt/IVolt.sol";

/// @title CoreRef interface
/// @author Volt & Fei Protocol
interface ICoreRefV2 {
    // ----------- Events -----------

    event CoreUpdate(address indexed oldCore, address indexed newCore);

    /// @notice emitted when the PCV Oracle address is updated
    event PCVOracleUpdated(address oldOracle, address newOracle);

    // ----------- Governor or Guardian only state changing api -----------

    function pause() external;

    function unpause() external;

    // ----------- Getters -----------

    function core() external view returns (ICoreV2);

    function volt() external view returns (IVoltBurn);

    function vcon() external view returns (IERC20);

    function pcvOracle() external view returns (IPCVOracle);

    function globalRateLimitedMinter() external view returns (IGRLM);
}
