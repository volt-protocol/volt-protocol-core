// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {IVolt} from "../../volt/IVolt.sol";
import {IPegStabilityModule} from "../IPegStabilityModule.sol";

interface ICurveRouter {
    // ---------- View-Only API ----------

    /// @notice reference to the Volt contract used.
    function volt() external returns (IVolt);

    /// @notice calculate the amount of VOLT out for a given `amountIn` of underlying
    function getMintAmountOut(
        uint256 amountIn,
        IPegStabilityModule psm,
        address curvePool,
        address tokenA,
        address tokenB
    ) external returns (uint256 amountTokenBReceived, uint256 amountVoltOut);

    /// @notice calculate the amount of underlying out for a given `amountVoltIn` of VOLT
    function getRedeemAmountOut(
        uint256 amountVoltIn,
        address tokenA,
        address tokenB
    ) external view returns (uint256 amountOut);

    // ---------- State-Changing API ----------

    /// @notice Mint volt for stablecoins via curve
    /// @param to, the address to mint Volt to
    /// @param amountIn, the amount of stablecoin to deposit
    /// @param psm, the PSM the router should mint from
    /// @param tokenA, the inital token that the user would like to swap
    /// @param tokenB, the token the user would route through
    /// @return amountVoltOut the amount of Volt returned from the mint function

    function mint(
        address to,
        uint256 amountIn,
        IPegStabilityModule psm,
        address curvePool,
        address tokenA,
        address tokenB
    ) external returns (uint256 amountVoltOut);

    /// @notice Redeems volt for stablecoin via curve
    /// @param to, the address to send redeemed stablecoin to
    /// @param amountVoltIn, the amount of VOLT to deposit
    /// @param minAmountOut, the minimum amount of stablecoin expected to be received
    /// @param psm, the PSM the router should redeem from
    /// @param tokenA, the token to route through on redemption
    /// @param tokenB, the token the user would like to redeem
    /// @return amountOut the amount of stablecoin returned from the mint function
    function redeem(
        address to,
        uint256 amountVoltIn,
        uint256 minAmountOut,
        address psm,
        address tokenA,
        address tokenB
    ) external returns (uint256 amountOut);
}
