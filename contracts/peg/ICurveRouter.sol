// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {IVolt} from "../volt/IVolt.sol";

interface ICurveRouter {
    // ---------- View-Only API ----------

    /// @notice reference to the Volt contract used.
    function volt() external returns (IVolt);

    /// @notice calculate the amount of VOLT out for a given `amountIn` of underlying
    function getMintAmountOut(uint256 amountIn)
        external
        view
        returns (uint256 amountVoltOut);

    /// @notice the maximum mint amount out
    function getMaxMintAmountOut() external view returns (uint256);

    /// @notice calculate the amount of underlying out for a given `amountVoltIn` of VOLT
    function getRedeemAmountOut(uint256 amountVoltIn)
        external
        view
        returns (uint256 amountOut);

    // ---------- State-Changing API ----------

    /// @notice Mint volt for stablecoins via curve
    /// @param to, the address to mint Volt to
    /// @param amountIn, the amount of stablecoin to deposit
    /// @param minAmountOut, the minimum amountOfVolt expected to be received
    /// @param psm, the PSM the router should mint from
    /// @return amountVoltOut the amount of Volt returned from the mint function

    function mint(
        address to,
        uint256 amountIn,
        uint256 minAmountOut,
        address psm,
        address[] memory path
    ) external returns (uint256 amountVoltOut);

    /// @notice Redeems volt for stablecoin via curve
    /// @param to, the address to send redeemed stablecoin to
    /// @param amountVoltIn, the amount of VOLT to deposit
    /// @param minAmountOut, the minimum amount of stablecoin expected to be received
    /// @param psm, the PSM the router should redeem from
    /// @return amountOut the amount of stablecoin returned from the mint function
    function redeem(
        address to,
        uint256 amountVoltIn,
        uint256 minAmountOut,
        address psm,
        address[] memory path
    ) external returns (uint256 amountOut);
}
