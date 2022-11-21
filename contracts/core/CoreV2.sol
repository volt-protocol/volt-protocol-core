// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IVolt} from "../volt/IVolt.sol";
import {IGRLM} from "../minter/IGRLM.sol";
import {ICoreV2} from "./ICoreV2.sol";
import {PermissionsV2} from "./PermissionsV2.sol";
import {GlobalReentrancyLock} from "./GlobalReentrancyLock.sol";

/// @title Source of truth for VOLT Protocol
/// @author Volt Protocol
/// @notice maintains roles, access control, Volt, Vcon, and the Vcon treasury
contract CoreV2 is ICoreV2, PermissionsV2, GlobalReentrancyLock {
    /// @notice address of the Volt token
    IVolt public override volt;

    /// @notice address of the Vcon token
    IERC20 public override vcon;

    /// @notice address of the global rate limited minter
    IGRLM public globalRateLimitedMinter;

    /// @notice construct CoreV2
    /// @param newVolt reference to the volt token
    constructor(address newVolt) PermissionsV2() {
        volt = IVolt(newVolt);

        /// msg.sender already has the VOLT Minting abilities, so grant them governor as well
        _setupRole(GOVERN_ROLE, msg.sender);
    }

    /// @notice governor only function to set the VCON token
    /// @param newVcon new vcon token
    function setVcon(IERC20 newVcon) external onlyGovernor {
        address oldVcon = address(vcon);
        vcon = newVcon;

        emit VconUpdate(oldVcon, address(newVcon));
    }

    /// @notice governor only function to set the VOLT token
    /// @param newVolt new volt token
    function setVolt(IVolt newVolt) external onlyGovernor {
        address oldVolt = address(volt);
        volt = newVolt;

        emit VoltUpdate(oldVolt, address(newVolt));
    }

    /// @notice governor only function to set the Global Rate Limited Minter
    /// @param newGlobalRateLimitedMinter new volt global rate limited minter
    function setGlobalRateLimitedMinter(
        IGRLM newGlobalRateLimitedMinter
    ) external onlyGovernor {
        address oldGrlm = address(globalRateLimitedMinter);
        globalRateLimitedMinter = newGlobalRateLimitedMinter;

        emit GlobalRateLimitedMinterUpdate(
            oldGrlm,
            address(newGlobalRateLimitedMinter)
        );
    }
}
