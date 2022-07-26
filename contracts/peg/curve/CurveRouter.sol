// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {ICurveRouter} from "./ICurveRouter.sol";
import {ICurvePool} from "./ICurvePool.sol";
import {IVolt} from "../../volt/IVolt.sol";
import {IPegStabilityModule} from "../IPegStabilityModule.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {MainnetAddresses} from "../../test/integration/fixtures/MainnetAddresses.sol";
import {CoreRef} from "../../refs/CoreRef.sol";

contract CurveRouter is ICurveRouter, CoreRef {
    using SafeERC20 for IERC20;
    using SafeCast for *;

    constructor(address _core, TokenApproval[9] memory tokenApprovals)
        CoreRef(_core)
    {
        unchecked {
            for (uint256 i = 0; i < tokenApprovals.length; i++) {
                IERC20(tokenApprovals[i].token).safeApprove(
                    tokenApprovals[i].contractToApprove,
                    type(uint256).max
                );
            }
        }
    }

    /// @notice calculate the amount of VOLT out for a given `amountIn` of underlying
    function getMintAmountOut(
        uint256 amountIn,
        IPegStabilityModule psm,
        address curvePool,
        address tokenA,
        address tokenB,
        uint256 noOfTokens
    )
        public
        view
        override
        returns (
            uint256 amountTokenBReceived,
            uint256 amountOut,
            uint256 index_i,
            uint256 index_j
        )
    {
        (amountTokenBReceived, index_i, index_j) = calculateSwap(
            amountIn,
            curvePool,
            tokenA,
            tokenB,
            noOfTokens
        );

        amountOut = psm.getMintAmountOut(amountTokenBReceived);
    }

    /// @notice calculate the amount of underlying out for a given `amountVoltIn` of VOLT
    function getRedeemAmountOut(
        uint256 amountVoltIn,
        IPegStabilityModule psm,
        address curvePool,
        address tokenA,
        address tokenB,
        uint256 noOfTokens
    )
        external
        view
        override
        returns (
            uint256 amountTokenAReceived,
            uint256 amountTokenBReceived,
            uint256 index_i,
            uint256 index_j
        )
    {
        amountTokenAReceived = psm.getRedeemAmountOut(amountVoltIn);

        (amountTokenBReceived, index_i, index_j) = calculateSwap(
            amountTokenAReceived,
            curvePool,
            tokenA,
            tokenB,
            noOfTokens
        );
    }

    /// @notice calculate the amount of VOLT out for a given `amountIn` of underlying
    function getMintAmountOutMetaPool(
        uint256 amountIn,
        IPegStabilityModule psm,
        address curvePool,
        uint256 index_i,
        uint256 index_j
    )
        external
        view
        override
        returns (uint256 amountTokenBReceived, uint256 amountOut)
    {
        amountTokenBReceived = calculateSwapUnderlying(
            amountIn,
            curvePool,
            index_i,
            index_j
        );

        amountOut = psm.getMintAmountOut(amountTokenBReceived);
    }

    /// @notice calculate the amount of underlying out for a given `amountVoltIn` of VOLT
    function getRedeemAmountOutMetaPool(
        uint256 amountVoltIn,
        IPegStabilityModule psm,
        address curvePool,
        uint256 index_i,
        uint256 index_j
    )
        external
        view
        override
        returns (uint256 amountTokenAReceived, uint256 amountTokenBReceived)
    {
        amountTokenAReceived = psm.getRedeemAmountOut(amountVoltIn);

        amountTokenBReceived = calculateSwapUnderlying(
            amountTokenAReceived,
            curvePool,
            index_i,
            index_j
        );
    }

    // ---------- State-Changing API ----------

    /// @notice Mint volt for stablecoins via curve
    /// @param to, the address to mint Volt to
    /// @param amountIn, the amount of stablecoin to deposit
    /// @param amountStableOut, the amount we expect to recieve from curve
    /// @param amountVoltOut the amount of Volt we should get out, calculated externally from PSM and passed here
    /// @param psm, the PSM the router should mint from
    /// @param tokenA, the inital token that the user would like to swap
    /// @return amountOut the amount of Volt returned from the mint function
    function mint(
        address to,
        uint256 amountIn,
        uint256 amountStableOut,
        uint256 amountVoltOut,
        IPegStabilityModule psm,
        address curvePool,
        address tokenA,
        uint256 index_i,
        uint256 index_j
    ) external override returns (uint256 amountOut) {
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountIn);

        ICurvePool(curvePool).exchange(
            index_i.toInt256().toInt128(),
            index_j.toInt256().toInt128(),
            amountIn,
            amountStableOut
        );

        amountOut = psm.mint(to, amountStableOut, amountVoltOut);
    }

    /// @notice Mint volt for stablecoins via curve
    /// @param to, the address to mint Volt to
    /// @param amountIn, the amount of stablecoin to deposit
    /// @param amountStableOut, the amount we expect to recieve from curve
    /// @param amountVoltOut the amount of Volt we should get out, calculated externally from PSM and passed here
    /// @param psm, the PSM the router should mint from
    /// @param tokenA, the inital token that the user would like to swap
    /// @return amountOut the amount of Volt returned from the mint function
    function mintMetaPool(
        address to,
        uint256 amountIn,
        uint256 amountStableOut,
        uint256 amountVoltOut,
        IPegStabilityModule psm,
        address curvePool,
        address tokenA,
        uint256 index_i,
        uint256 index_j
    ) external override returns (uint256 amountOut) {
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountIn);

        ICurvePool(curvePool).exchange_underlying(
            index_i.toInt256().toInt128(),
            index_j.toInt256().toInt128(),
            amountIn,
            amountStableOut
        );

        amountOut = psm.mint(to, amountStableOut, amountVoltOut);
    }

    /// @notice Redeems volt for stable via PSM then performs swap on curve
    /// @param to, the address to send redeemed stablecoin to
    /// @param amountVoltIn, the amount of VOLT to deposit
    /// @param amountStableOut, the amount of stablecoin we expect from the PSM
    /// @param minAmountOut, the minimum amount of asset we expect to receive from curve
    /// @param psm, the PSM the router should redeem from
    /// @param tokenB, the token the user would like to redeem
    /// @return amountOut the amount of stablecoin returned from the mint function
    function redeem(
        address to,
        uint256 amountVoltIn,
        uint256 amountStableOut,
        uint256 minAmountOut,
        IPegStabilityModule psm,
        address curvePool,
        address tokenB,
        uint256 index_i,
        uint256 index_j
    ) external override returns (uint256) {
        volt().transferFrom(msg.sender, address(this), amountVoltIn);
        psm.redeem(address(this), amountVoltIn, amountStableOut);

        ICurvePool(curvePool).exchange(
            index_i.toInt256().toInt128(),
            index_j.toInt256().toInt128(),
            amountStableOut,
            minAmountOut
        );

        IERC20(tokenB).safeTransfer(to, minAmountOut);

        return minAmountOut;
    }

    /// @notice Redeems volt for stable via PSM then performs swap on curve
    /// @param to, the address to send redeemed stablecoin to
    /// @param amountVoltIn, the amount of VOLT to deposit
    /// @param amountStableOut, the amount of stablecoin we expect from the PSM
    /// @param minAmountOut, the minimum amount of asset we expect to receive from curve
    /// @param psm, the PSM the router should redeem from
    /// @param tokenB, the token the user would like to redeem
    /// @return amountOut the amount of stablecoin returned from the mint function
    function redeemMetaPool(
        address to,
        uint256 amountVoltIn,
        uint256 amountStableOut,
        uint256 minAmountOut,
        IPegStabilityModule psm,
        address curvePool,
        address tokenB,
        uint256 index_i,
        uint256 index_j
    ) external override returns (uint256) {
        volt().transferFrom(msg.sender, address(this), amountVoltIn);
        psm.redeem(address(this), amountVoltIn, amountStableOut);

        ICurvePool(curvePool).exchange_underlying(
            index_i.toInt256().toInt128(),
            index_j.toInt256().toInt128(),
            amountStableOut,
            minAmountOut
        );

        IERC20(tokenB).safeTransfer(to, minAmountOut);

        return minAmountOut;
    }

    function calculateSwap(
        uint256 amountIn,
        address curvePool,
        address tokenA,
        address tokenB,
        uint256 noOfTokens
    )
        public
        view
        returns (
            uint256 amountTokenBReceived,
            uint256 index_i,
            uint256 index_j
        )
    {
        for (uint256 i = 0; i < noOfTokens; i++) {
            if (ICurvePool(curvePool).coins(i) == tokenA) {
                index_i = i;
            }

            if (ICurvePool(curvePool).coins(i) == tokenB) {
                index_j = i;
            }
        }

        amountTokenBReceived =
            (ICurvePool(curvePool).get_dy(
                index_i.toInt256().toInt128(),
                index_j.toInt256().toInt128(),
                amountIn
            ) * 9999) /
            10000;
    }

    function calculateSwapUnderlying(
        uint256 amountIn,
        address curvePool,
        uint256 index_i,
        uint256 index_j
    ) public view returns (uint256 amountTokenBReceived) {
        amountTokenBReceived =
            (ICurvePool(curvePool).get_dy_underlying(
                index_i.toInt256().toInt128(),
                index_j.toInt256().toInt128(),
                amountIn
            ) * 9999) /
            10000;
    }

    function setTokenApproval(TokenApproval[] memory tokenApprovals)
        external
        override
        onlyGovernor
    {
        unchecked {
            for (uint256 i = 0; i < tokenApprovals.length; i++) {
                IERC20(tokenApprovals[i].token).safeApprove(
                    tokenApprovals[i].contractToApprove,
                    type(uint256).max
                );
            }
        }
    }
}
