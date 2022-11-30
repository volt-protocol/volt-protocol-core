// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

/// @title a PCV Router interface
/// @author Volt Protocol
interface IPCVRouter {
    // ----------- Events -----------

    event PCVMovement(
        address indexed source,
        address indexed destination,
        uint256 amount
    );

    // ----------- PCV_MOVER role API -----------

    function movePCV(
        address source,
        address destination,
        bool sourceIsLiquid,
        bool destinationIsLiquid,
        uint256 amount
    ) external;

    // ----------- PCV_CONTROLLER role api -----------

    function movePCVUnchecked(
        address source,
        address destination,
        uint256 amount
    ) external;

    function moveAllPCVUnchecked(address source, address destination) external;
}
