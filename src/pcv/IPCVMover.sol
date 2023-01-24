// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

interface IPCVMover {
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
}
