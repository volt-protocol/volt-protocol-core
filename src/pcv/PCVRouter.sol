// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {PCVMover} from "@voltprotocol/pcv/PCVMover.sol";
import {CoreRefV2} from "@voltprotocol/refs/CoreRefV2.sol";
import {VoltRoles} from "@voltprotocol/core/VoltRoles.sol";
import {IPCVOracle} from "@voltprotocol/oracle/IPCVOracle.sol";
import {IPCVRouter} from "@voltprotocol/pcv/IPCVRouter.sol";
import {IPCVSwapper} from "@voltprotocol/pcv/IPCVSwapper.sol";
import {IPCVDeposit} from "@voltprotocol/pcv/IPCVDeposit.sol";

/// @title Volt Protocol PCV Router
/// @notice A contract that allows PCV movements between deposits.
/// @dev This contract requires the PCV_CONTROLLER role.
/// @author eswak
contract PCVRouter is IPCVRouter, CoreRefV2, PCVMover {
    constructor(address _core) CoreRefV2(_core) {}

    // ---------- PCV Movement API ---------------

    /// @notice Move PCV by withdrawing it from a PCVDeposit and deposit it in
    /// a destination PCVDeposit.
    /// This function requires the highly trusted PCV_CONTROLLER role, and expects
    /// caller to know what they are doing by disabling checks such as the fact
    /// that the 2 PCV Deposits passed as parameter are indeed contracts of the
    /// Volt Protocol, and that they are compatible for a PCV movement (same token,
    /// or using a compatible PCV swapper).
    /// @param source the address of the pcv deposit contract to withdraw from
    /// @param destination the address of the pcv deposit contract to deposit into
    /// @param swapper the PCVSwapper to use for asset conversion, address(0) for no conversion.
    /// @param amount the amount to withdraw and deposit
    /// @param sourceAsset the token address of the source PCV Deposit
    /// @param destinationAsset the token address of the destination PCV Deposit
    function movePCVUnchecked(
        address source,
        address destination,
        address swapper,
        uint256 amount,
        address sourceAsset,
        address destinationAsset
    ) external whenNotPaused onlyPCVController globalLock(1) {
        _movePCV(
            source,
            destination,
            swapper,
            amount,
            sourceAsset,
            destinationAsset
        );
    }

    /// @notice Move all PCV in a source PCVDeposit and deposit it in
    /// a destination PCVDeposit.
    /// This function requires the highly trusted PCV_CONTROLLER role, see {movePCVUnchecked}.
    /// @param source the address of the pcv deposit contract to withdraw from
    /// @param destination the address of the pcv deposit contract to deposit into
    /// @param swapper the PCVSwapper to use for asset conversion, address(0) for no conversion.
    /// @param sourceAsset the token address of the source PCV Deposit
    /// @param destinationAsset the token address of the destination PCV Deposit
    function moveAllPCVUnchecked(
        address source,
        address destination,
        address swapper,
        address sourceAsset,
        address destinationAsset
    ) external whenNotPaused onlyPCVController globalLock(1) {
        uint256 amount = IPCVDeposit(source).balance();
        _movePCV(
            source,
            destination,
            swapper,
            amount,
            sourceAsset,
            destinationAsset
        );
    }
}
