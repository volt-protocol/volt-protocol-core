// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IPCVOracle} from "@voltprotocol/oracle/IPCVOracle.sol";
import {IVolt, IERC20} from "@voltprotocol/volt/IVolt.sol";
import {IPermissionsV2} from "@voltprotocol/core/IPermissionsV2.sol";
import {IGlobalReentrancyLock} from "@voltprotocol/core/IGlobalReentrancyLock.sol";
import {IGlobalRateLimitedMinter} from "@voltprotocol/rate-limits/IGlobalRateLimitedMinter.sol";
import {IGlobalSystemExitRateLimiter} from "@voltprotocol/rate-limits/IGlobalSystemExitRateLimiter.sol";

/// @title Core Interface
/// @author Volt Protocol
interface ICoreV2 is IPermissionsV2 {
    // ----------- Events -----------

    /// @notice emitted with reference to VOLT token is updated
    event VoltUpdate(address indexed oldVolt, address indexed newVolt);

    /// @notice emitted when reference to VCON token is updated
    event VconUpdate(address indexed oldVcon, address indexed newVcon);

    /// @notice emitted when reference to global rate limited minter is updated
    event GlobalRateLimitedMinterUpdate(
        address indexed oldGrlm,
        address indexed newGrlm
    );

    /// @notice emitted when reference to PCV oracle is updated
    event PCVOracleUpdate(
        address indexed oldPcvOracle,
        address indexed newPcvOracle
    );

    /// @notice emitted when reference to global system exit rate limiter is updated
    event GlobalSystemExitRateLimiterUpdate(
        address indexed oldGserl,
        address indexed newGserl
    );

    /// @notice emitted when reference to global reentrancy lock is updated
    event GlobalReentrancyLockUpdate(
        address indexed oldGrl,
        address indexed newGrl
    );

    // ----------- Getters -----------

    /// @notice returns reference to the VOLT token contract
    function volt() external view returns (IVolt);

    /// @notice returns reference to the VCON token contract
    function vcon() external view returns (IERC20);

    /// @notice returns reference to the global rate limited minter
    function globalRateLimitedMinter()
        external
        view
        returns (IGlobalRateLimitedMinter);

    /// @notice returns reference to the pcv oracle
    function pcvOracle() external view returns (IPCVOracle);

    /// @notice returns reference to the global reentrancy lock
    function globalReentrancyLock()
        external
        view
        returns (IGlobalReentrancyLock);

    // ----------- Governance Only API -----------

    /// @notice governor only function to set the Global Reentrancy Lock
    /// @param newGlobalReentrancyLock new global reentrancy lock
    function setGlobalReentrancyLock(
        IGlobalReentrancyLock newGlobalReentrancyLock
    ) external;

    /// @notice governor only function to set the Global Rate Limited Minter
    /// @param newGlobalRateLimitedMinter new volt global rate limited minter
    function setGlobalRateLimitedMinter(
        IGlobalRateLimitedMinter newGlobalRateLimitedMinter
    ) external;

    /// @notice governor only function to set the Global Rate Limited Minter
    /// @param newGlobalSystemExitRateLimiter new volt global rate limited minter
    function setGlobalSystemExitRateLimiter(
        IGlobalSystemExitRateLimiter newGlobalSystemExitRateLimiter
    ) external;

    /// @notice governor only function to set the PCV Oracle
    /// @param newPCVOracle new volt pcv oracle
    function setPCVOracle(IPCVOracle newPCVOracle) external;

    /// @notice governor only function to set the VOLT token
    /// @param newVolt new volt token
    function setVolt(IVolt newVolt) external;

    /// @notice governor only function to set the VCON token
    /// @param newVcon new vcon token
    function setVcon(IERC20 newVcon) external;
}