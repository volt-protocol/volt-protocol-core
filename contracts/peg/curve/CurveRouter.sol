// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {ICurveRouter} from "./ICurveRouter.sol";
import {ICurvePool} from "./ICurvePool.sol";
import {IVolt} from "../../volt/IVolt.sol";
import {IPegStabilityModule} from "../IPegStabilityModule.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "hardhat/console.sol";

import {Constants} from "../../Constants.sol";

contract CurveRouter is ICurveRouter {
    using SafeERC20 for IERC20;

    /// @notice reference to the Volt contract used.
    /// Router can be redeployed if Volt address changes
    IVolt public immutable override volt;

    constructor(IVolt _volt) {
        volt = _volt;
    }

    /// @notice calculate the amount of VOLT out for a given `amountIn` of underlying
    function getMintAmountOut(
        uint256 amountIn,
        IPegStabilityModule psm,
        address curvePool,
        address tokenA,
        address tokenB
    )
        public
        view
        override
        returns (uint256 amountTokenBReceived, uint256 amountVoltOut)
    {
        (amountTokenBReceived, amountVoltOut, , ) = _calculateSwap(
            amountIn,
            psm,
            curvePool,
            tokenA,
            tokenB
        );
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
        address curvePool,
        address tokenA,
        address tokenB
    ) external override returns (uint256 amountOut) {
        (
            uint256 amountTokenBReceived,
            uint256 amountVoltOut,
            int256 index_i,
            int256 index_j
        ) = _calculateSwap(amountIn, psm, curvePool, tokenA, tokenB);

        IERC20(tokenA).transferFrom(msg.sender, address(this), amountIn);

        IERC20(tokenA).approve(address(curvePool), type(uint256).max);

        ICurvePool(curvePool).exchange(
            int128(index_i),
            int128(index_j),
            amountIn,
            amountTokenBReceived
        );

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

    // ---------- Private functions ----------

    function _calculateSwap(
        uint256 amountIn,
        IPegStabilityModule psm,
        address curvePool,
        address tokenA,
        address tokenB
    )
        private
        view
        returns (
            uint256 amountTokenBReceived,
            uint256 amountVoltOut,
            int256 index_i,
            int256 index_j
        )
    {
        require(
            address(psm.underlyingToken()) == tokenB,
            "CurveRouter: Unsupported Token"
        );

        // todo to be able to search up to 4 tokens -- curve reverts the call when accessing an index that doesn't exist
        // maybe pass number of tokens in the pool in the function

        for (int256 i = 0; i < 3; i++) {
            if (ICurvePool(curvePool).coins(uint256(i)) == tokenA) {
                index_i = i;
            }

            if (ICurvePool(curvePool).coins(uint256(i)) == tokenB) {
                index_j = i;
            }
        }

        // console.log(uint256(index_i), uint256(index_j));

        amountTokenBReceived = ICurvePool(curvePool).get_dy(
            int128(index_i),
            int128(index_j),
            amountIn
        );

        amountVoltOut = psm.getMintAmountOut(amountTokenBReceived);
    }
}
