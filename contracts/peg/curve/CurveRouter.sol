// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {ICurveRouter} from "./ICurveRouter.sol";
import {ICurvePool} from "./ICurvePool.sol";
import {IVolt} from "../../volt/IVolt.sol";
import {IPegStabilityModule} from "../IPegStabilityModule.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {MainnetAddresses} from "../../test/integration/fixtures/MainnetAddresses.sol";
import {Constants} from "../../Constants.sol";
import "hardhat/console.sol";

contract CurveRouter is ICurveRouter {
    using SafeERC20 for IERC20;
    using SafeCast for *;

    /// @notice reference to the Volt contract used.
    /// Router can be redeployed if Volt address changes
    IVolt public immutable override volt;

    constructor(IVolt _volt) {
        volt = _volt;

        IERC20(MainnetAddresses.VOLT).approve(
            address(MainnetAddresses.VOLT_USDC_PSM),
            type(uint256).max
        );
        IERC20(MainnetAddresses.USDC).approve(
            address(MainnetAddresses.VOLT_USDC_PSM),
            type(uint256).max
        );

        IERC20(MainnetAddresses.USDC).approve(
            address(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL),
            type(uint256).max
        );

        IERC20(MainnetAddresses.USDT).safeApprove(
            address(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL),
            type(uint256).max
        );
        IERC20(MainnetAddresses.DAI).approve(
            address(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL),
            type(uint256).max
        );
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
        returns (uint256 amountTokenAReceived, uint256 amountTokenBReceived)
    {
        amountTokenAReceived = psm.getRedeemAmountOut(amountVoltIn);

        (amountTokenBReceived, , ) = calculateSwap(
            amountTokenAReceived,
            curvePool,
            tokenA,
            tokenB,
            noOfTokens
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

    /// @notice Redeems volt for stablecoin via curve
    /// @param to, the address to send redeemed stablecoin to
    /// @param amountVoltIn, the amount of VOLT to deposit
    /// @param amountStableOut, the amount of stablecoin we expect from the PSM
    /// @param minAmountOut, the minimum amount of stablecoin expect to receive from curve
    /// @param psm, the PSM the router should redeem from
    /// @param tokenA, the token to route through on redemption
    /// @param tokenB, the token the user would like to redeem
    /// @return amountOut the amount of stablecoin returned from the mint function
    function redeem(
        address to,
        uint256 amountVoltIn,
        uint256 amountStableOut,
        uint256 minAmountOut,
        IPegStabilityModule psm,
        address curvePool,
        address tokenA,
        address tokenB,
        uint256 noOfTokens
    ) external override returns (uint256) {
        volt.transferFrom(msg.sender, address(this), amountVoltIn);

        psm.redeem(address(this), amountVoltIn, amountStableOut);

        (, uint256 index_i, uint256 index_j) = calculateSwap(
            amountStableOut,
            curvePool,
            tokenA,
            tokenB,
            noOfTokens
        );

        ICurvePool(curvePool).exchange(
            index_i.toInt256().toInt128(),
            index_j.toInt256().toInt128(),
            amountStableOut,
            minAmountOut
        );

        IERC20(tokenB).transferFrom(address(this), to, minAmountOut);

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
}
