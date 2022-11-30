// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IPCVRouter} from "./IPCVRouter.sol";
import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {IPCVDeposit} from "./IPCVDeposit.sol";
import {VoltRoles} from "../core/VoltRoles.sol";
import {PCVOracle} from "../oracle/PCVOracle.sol";

/// @title Volt Protocol PCV Router
/// @notice A contract that allows PCV movements between deposits.
/// @dev This contract requires the PCV_CONTROLLER role.
/// @author eswak
contract PCVRouter is IPCVRouter, CoreRefV2 {
    constructor(address _core) CoreRefV2(_core) {}

    /// @notice Move PCV by withdrawing it from a PCVDeposit and deposit it in
    /// a destination PCVDeposit.
    /// This function requires a less trusted PCV_MOVER role, and performs checks
    /// at runtime that the PCV Deposits are indeed added in the PCV Oracle, and
    /// that both PCV Deposits use the same token.
    /// @param source the address of the pcv deposit contract to withdraw from
    /// @param destination the address of the pcv deposit contract to deposit into
    /// @param sourceIsLiquid true if {source} is a liquid PCVDeposit
    /// @param destinationIsLiquid true if {destination} is a liquid PCVDeposit
    /// @param amount the amount to withdraw and deposit
    function movePCV(
        address source,
        address destination,
        bool sourceIsLiquid,
        bool destinationIsLiquid,
        uint256 amount
    ) external whenNotPaused onlyVoltRole(VoltRoles.PCV_MOVER) globalLock(1) {
        // Check both deposits are still valid for PCVOracle
        address _pcvOracle = pcvOracle;
        require(
            (
                sourceIsLiquid
                    ? PCVOracle(_pcvOracle).isLiquidVenue(source)
                    : PCVOracle(_pcvOracle).isIlliquidVenue(source)
            ),
            "PCVRouter: invalid source"
        );
        require(
            (
                destinationIsLiquid
                    ? PCVOracle(_pcvOracle).isLiquidVenue(destination)
                    : PCVOracle(_pcvOracle).isIlliquidVenue(destination)
            ),
            "PCVRouter: invalid destination"
        );
        // Check compatibility of the underlying tokens
        require(
            IPCVDeposit(source).balanceReportedIn() ==
                IPCVDeposit(destination).balanceReportedIn(),
            "PCVRouter: invalid route"
        );

        // Do movement
        _movePCV(source, destination, amount);
    }

    /// @notice Move PCV by withdrawing it from a PCVDeposit and deposit it in
    /// a destination PCVDeposit.
    /// This function requires the highly trusted PCV_CONTROLLER role, and expects
    /// caller to know what they are doing by disabling checks such as the fact
    /// that the 2 PCV Deposits passed as parameter are indeed contracts of the
    /// Volt Protocol, and that they are compatible for a PCV movement (same token).
    /// @param source the address of the pcv deposit contract to withdraw from
    /// @param destination the address of the pcv deposit contract to deposit into
    /// @param amount the amount to withdraw and deposit
    function movePCVUnchecked(
        address source,
        address destination,
        uint256 amount
    ) external whenNotPaused onlyPCVController globalLock(1) {
        _movePCV(source, destination, amount);
    }

    /// @notice Move all PCV in a source PCVDeposit and deposit it in
    /// a destination PCVDeposit.
    /// This function requires the highly trusted PCV_CONTROLLER role, see {movePCVUnchecked}.
    /// @param source the address of the pcv deposit contract to withdraw from
    /// @param destination the address of the pcv deposit contract to deposit into
    function moveAllPCVUnchecked(
        address source,
        address destination
    ) external whenNotPaused onlyPCVController globalLock(1) {
        uint256 amount = IPCVDeposit(source).balance();
        _movePCV(source, destination, amount);
    }

    /// ------------- Helper Methods -------------
    function _movePCV(
        address source,
        address destination,
        uint256 amount
    ) internal {
        // Do transfer
        IPCVDeposit(source).withdraw(destination, amount);
        IPCVDeposit(destination).deposit();

        // Emit event
        emit PCVMovement(source, destination, amount);
    }
}
