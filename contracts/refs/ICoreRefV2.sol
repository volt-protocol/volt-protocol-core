// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IGRLM} from "../limiter/IGRLM.sol";
import {IGSERL} from "../limiter/IGSERL.sol";
import {ICoreV2} from "../core/ICoreV2.sol";
import {IVolt, IVoltBurn} from "../volt/IVolt.sol";

/// @title CoreRef interface
/// @author Volt Protocol
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

    function voltBalance() external view returns (uint256);

    function vconBalance() external view returns (uint256);

    function globalRateLimitedMinter() external view returns (IGRLM);

    function globalSystemExitRateLimiter() external view returns (IGSERL);
}
