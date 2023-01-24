// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

/// @title a PCV Router interface
/// @author Volt Protocol
interface IPCVRouter {
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
