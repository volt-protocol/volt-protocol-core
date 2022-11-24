// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {IPCVDeposit} from "./IPCVDeposit.sol";
import {VoltRoles} from "../core/VoltRoles.sol";
import {PCVOracle} from "../oracle/PCVOracle.sol";

/// @title Volt Protocol PCV Router
/// @notice A contract that allows PCV movements between deposits.
/// @dev This contract requires the PCV_CONTROLLER role.
/// @author eswak
contract PCVRouter is CoreRefV2 {
    event PCVMovement(
        address indexed source,
        address indexed destination,
        uint256 amount
    );

    constructor(address _core) CoreRefV2(_core) {}

    /// @notice Move PCV by withdrawing it from a PCVDeposit and deposit it in
    /// a destination PCVDeposit.
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

        // Do transfer
        IPCVDeposit(source).withdraw(destination, amount);
        IPCVDeposit(destination).deposit();

        // Emit event
        emit PCVMovement(source, destination, amount);
    }
}
