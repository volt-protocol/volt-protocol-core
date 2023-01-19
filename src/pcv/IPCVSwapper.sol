// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

/// @title a PCV Swapper interface
/// @author Volt Protocol
interface IPCVSwapper {
    // ----------- Events -----------------------

    event Swap(
        address indexed assetIn,
        address indexed assetOut,
        address indexed destination,
        uint256 amountIn,
        uint256 amountOut
    );

    // ----------- View API ---------------------

    function canSwap(
        address assetIn,
        address assetOut
    ) external view returns (bool);

    // ----------- State-changing API -----------

    function swap(
        address assetIn,
        address assetOut,
        address destination
    ) external returns (uint256);
}
