// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IGRLM} from "../minter/IGRLM.sol";
import {IVolt, IERC20} from "../volt/IVolt.sol";
import {IPermissionsV2} from "./IPermissionsV2.sol";

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

    // ----------- Getters -----------

    /// @notice returns reference to the VOLT token contract
    function volt() external view returns (IVolt);

    /// @notice returns reference to the VCON token contract
    function vcon() external view returns (IERC20);

    /// @notice returns reference to the global rate limited minter
    function globalRateLimitedMinter() external view returns (IGRLM);

    // ----------- Governance Only API -----------

    /// @notice governor only function to set the Global Rate Limited Minter
    /// @param newGlobalRateLimitedMinter new volt global rate limited minter
    function setGlobalRateLimitedMinter(
        IGRLM newGlobalRateLimitedMinter
    ) external;

    /// @notice governor only function to set the VOLT token
    /// @param newVolt new volt token
    function setVolt(IVolt newVolt) external;

    /// @notice governor only function to set the VCON token
    /// @param newVcon new vcon token
    function setVcon(IERC20 newVcon) external;
}
