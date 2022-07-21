// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {ICurveRouter} from "./ICurveRouter.sol";
import {ICurvePool} from "./ICurvePool.sol";
import {ICurveFactory} from "./ICurveFactory.sol";
import {IVolt} from "../../volt/IVolt.sol";
import {IPegStabilityModule} from "../IPegStabilityModule.sol";

contract CurveRouter is ICurveRouter {
    /// @notice reference to the Volt contract used.
    /// Router can be redeployed if Volt address changes
    IVolt public immutable override volt;

    /// @notice the curve factory contract being used
    ICurveFactory public immutable override curveFactory;

    constructor(IVolt _volt, ICurveFactory _curveFactory) {
        volt = _volt;
        curveFactory = _curveFactory;
    }

    /// @notice calculate the amount of VOLT out for a given `amountIn` of underlying
    function getMintAmountOut(
        uint256 amountIn,
        IPegStabilityModule psm,
        address tokenA,
        address tokenB
    )
        public
        override
        returns (uint256 amountTokenBReceived, uint256 amountVoltOut)
    {
        require(
            address(psm.underlyingToken()) == tokenB,
            "CurveRouter: Unsupported Token "
        );
        uint128 index_i;
        uint128 index_j;

        address curvePool = curveFactory.find_pool_for_coins(tokenA, tokenB);

        require(
            curvePool != address(0),
            "CurveRouter: Swaps are not poassible for this pair"
        );

        // most pools have a maxiumum of 4 tokens
        unchecked {
            for (uint128 i = 0; i < 5; i++) {
                if (ICurvePool(curvePool).coins(i) == tokenA) {
                    index_i = i;
                }

                if (ICurvePool(curvePool).coins(i) == tokenB) {
                    index_j = i;
                }
            }
        }

        amountTokenBReceived = ICurvePool(curvePool).get_dy(
            int128(index_i),
            int128(index_j),
            amountIn
        );

        amountVoltOut = psm.getMintAmountOut(amountTokenBReceived);
    }

    /// @notice calculate the amount of underlying out for a given `amountVoltIn` of VOLT
    function getRedeemAmountOut(
        uint256 amountVoltIn,
        address tokenA,
        address tokenB
    ) external view override returns (uint256 amountOut) {}

    // ---------- State-Changing API ----------

    /// @notice Mint volt for stablecoins via curve
    /// @param to, the address to mint Volt to
    /// @param psm, the PSM the router should mint from
    /// @param tokenA, the inital token that the user would like to swap
    /// @param tokenB, the token the user would route through
    /// @return amountOut the amount of Volt returned from the mint function

    function mint(
        address to,
        uint256 amountIn,
        IPegStabilityModule psm,
        address tokenA,
        address tokenB
    ) external override returns (uint256 amountOut) {
        (
            uint256 amountTokenBReceived,
            uint256 amountVoltOut
        ) = getMintAmountOut(amountIn, psm, tokenA, tokenB);

        amountOut = psm.mint(to, amountTokenBReceived, amountVoltOut);
    }

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
    ) external override returns (uint256 amountOut) {}
}
