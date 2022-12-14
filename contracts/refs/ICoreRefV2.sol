// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ICoreV2} from "../core/ICoreV2.sol";
import {IPCVOracle} from "../oracle/IPCVOracle.sol";
import {IVolt, IVoltBurn} from "../volt/IVolt.sol";
import {IGlobalReentrancyLock} from "../core/IGlobalReentrancyLock.sol";
import {IGlobalRateLimitedMinter} from "../limiter/IGlobalRateLimitedMinter.sol";
import {IGlobalSystemExitRateLimiter} from "../limiter/IGlobalSystemExitRateLimiter.sol";

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

    // ----------- Getter -----------

    function core() external view returns (ICoreV2);
}
