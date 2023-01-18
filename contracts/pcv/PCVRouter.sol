// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {VoltRoles} from "../core/VoltRoles.sol";
import {IPCVOracle} from "../oracle/IPCVOracle.sol";
import {IPCVRouter} from "./IPCVRouter.sol";
import {IPCVSwapper} from "./IPCVSwapper.sol";
import {IPCVDeposit} from "./IPCVDeposit.sol";

/// @title Volt Protocol PCV Router
/// @notice A contract that allows PCV movements between deposits.
/// @dev This contract requires the PCV_CONTROLLER role.
/// @author eswak
contract PCVRouter is IPCVRouter, CoreRefV2 {
    using EnumerableSet for EnumerableSet.AddressSet;

    ///@notice set of whitelisted PCV swappers
    EnumerableSet.AddressSet private pcvSwappers;

    constructor(address _core) CoreRefV2(_core) {}

    // ---------- Read-Only API ------------------

    /// @notice returns true if the the provided address is a valid swapper to use
    /// @param pcvSwapper the pcvSwapper address to check if whitelisted
    function isPCVSwapper(
        address pcvSwapper
    ) public view override returns (bool) {
        return pcvSwappers.contains(pcvSwapper);
    }

    /// @notice returns all whitelisted PCV swappers
    function getPCVSwappers()
        external
        view
        override
        returns (address[] memory)
    {
        return pcvSwappers.values();
    }

    // ---------- PCVSwapper Management API ------

    /// @notice Add multiple PCV Swappers to the whitelist
    /// @param _pcvSwappers the addresses to whitelist, as calldata
    function addPCVSwappers(
        address[] calldata _pcvSwappers
    ) external override onlyGovernor {
        unchecked {
            for (uint256 i = 0; i < _pcvSwappers.length; i++) {
                require(
                    pcvSwappers.add(_pcvSwappers[i]),
                    "PCVRouter: Failed to add swapper"
                );
                emit PCVSwapperAdded(_pcvSwappers[i]);
            }
        }
    }

    /// @notice Remove multiple PCV Swappers from the whitelist
    /// @param _pcvSwappers the addresses to remove from whitelist, as calldata
    function removePCVSwappers(
        address[] calldata _pcvSwappers
    ) external override onlyGovernor {
        unchecked {
            for (uint256 i = 0; i < _pcvSwappers.length; i++) {
                require(
                    pcvSwappers.remove(_pcvSwappers[i]),
                    "PCVRouter: Failed to remove swapper"
                );
                emit PCVSwapperRemoved(_pcvSwappers[i]);
            }
        }
    }

    // ---------- PCV Movement API ---------------

    /// @notice Move PCV by withdrawing it from a PCVDeposit and deposit it in
    /// a destination PCVDeposit, eventually using a PCVSwapper in-between
    /// for asset conversion.
    /// This function requires a less trusted PCV_MOVER role, and performs checks
    /// at runtime that the PCV Deposits are indeed added in the PCV Oracle, that
    /// underlying tokens are correct, and that the PCVSwapper used (if any) has
    /// previously been whitelisted through governance.
    /// @param source the address of the pcv deposit contract to withdraw from
    /// @param destination the address of the pcv deposit contract to deposit into
    /// @param swapper the PCVSwapper to use for asset conversion, address(0) for no conversion.
    /// @param amount the amount to withdraw and deposit
    /// @param sourceAsset the token address of the source PCV Deposit
    /// @param destinationAsset the token address of the destination PCV Deposit
    function movePCV(
        address source,
        address destination,
        address swapper,
        uint256 amount,
        address sourceAsset,
        address destinationAsset
    ) external whenNotPaused onlyVoltRole(VoltRoles.PCV_MOVER) globalLock(1) {
        // Check both deposits are still valid for PCVOracle
        IPCVOracle _pcvOracle = pcvOracle();
        require(_pcvOracle.isVenue(source), "PCVRouter: invalid source");
        require(
            _pcvOracle.isVenue(destination),
            "PCVRouter: invalid destination"
        );

        // Check underlying tokens
        require(
            IPCVDeposit(source).balanceReportedIn() == sourceAsset,
            "PCVRouter: invalid source asset"
        );
        require(
            IPCVDeposit(destination).balanceReportedIn() == destinationAsset,
            "PCVRouter: invalid destination asset"
        );
        // Check swapper, if applicable
        if (swapper != address(0)) {
            require(isPCVSwapper(swapper), "PCVRouter: invalid swapper");
            require(
                IPCVSwapper(swapper).canSwap(sourceAsset, destinationAsset),
                "PCVRouter: unsupported swap"
            );
        }

        // Do movement
        _movePCV(
            source,
            destination,
            swapper,
            amount,
            sourceAsset,
            destinationAsset
        );
    }

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

    /// ------------- Helper Methods -------------
    function _movePCV(
        address source,
        address destination,
        address swapper,
        uint256 amountSource,
        address sourceAsset,
        address destinationAsset
    ) internal {
        // Do transfer
        uint256 amountDestination;
        if (swapper != address(0)) {
            IPCVDeposit(source).withdraw(swapper, amountSource);
            amountDestination = IPCVSwapper(swapper).swap(
                sourceAsset,
                destinationAsset,
                destination
            );
        } else {
            IPCVDeposit(source).withdraw(destination, amountSource);
            amountDestination = amountSource;
        }
        IPCVDeposit(destination).deposit();

        // Emit event
        emit PCVMovement(source, destination, amountSource, amountDestination);
    }
}
