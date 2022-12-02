// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

/// @title a PCV Router interface
/// @author Volt Protocol
interface IPCVRouter {
    // ----------- Events -----------

    event PCVMovement(
        address indexed source,
        address indexed destination,
        uint256 amountSource,
        uint256 amountDestination
    );

    event PCVSwapperAdded(address indexed swapper);

    event PCVSwapperRemoved(address indexed swapper);

    // ---------- Read-Only API ------------------

    function isPCVSwapper(address pcvSwapper) external returns (bool);

    function getPCVSwappers() external returns (address[] memory);

    // ---------- PCVSwapper Management API ------

    function addPCVSwappers(address[] calldata _pcvSwappers) external;

    function removePCVSwappers(address[] calldata _pcvSwappers) external;

    // ----------- PCV_MOVER role API -----------

    function movePCV(
        address source,
        address destination,
        address swapper,
        uint256 amount,
        address sourceAsset,
        address destinationAsset,
        bool sourceIsLiquid,
        bool destinationIsLiquid
    ) external;

    // ----------- PCV_CONTROLLER role api -----------

    function movePCVUnchecked(
        address source,
        address destination,
        address swapper,
        uint256 amount,
        address sourceAsset,
        address destinationAsset
    ) external;

    function moveAllPCVUnchecked(
        address source,
        address destination,
        address swapper,
        address sourceAsset,
        address destinationAsset
    ) external;
}
