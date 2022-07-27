// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {IVolt} from "../../volt/IVolt.sol";
import {IPegStabilityModule} from "../IPegStabilityModule.sol";

interface ICurveRouter {
    struct TokenApproval {
        address token;
        address contractToApprove;
    }

    // ---------- View-Only API ----------

    /// @notice calculate the amount of VOLT out for a given `amountIn` of asset from curve
    function getMintAmountOut(
        uint256 amountIn,
        IPegStabilityModule psm,
        address curvePool,
        address tokenA,
        address tokenB,
        uint256 noOfTokens
    )
        external
        returns (
            uint256 amountTokenBReceived,
            uint256 amountOut,
            uint256 index_i,
            uint256 index_j
        );

    /// @notice calculate the amount of an asset out for a given `amountVoltIn` of VOLT
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
        returns (
            uint256 amountTokenBReceived,
            uint256 amountOut,
            uint256 index_i,
            uint256 index_j
        );

    /// @notice calculate the amount of VOLT out for a given `amountIn` of asset from curve
    /// @dev indexes of tokens in curve pool must be known beforehand
    function getMintAmountOutMetaPool(
        uint256 amountIn,
        IPegStabilityModule psm,
        address curvePool,
        uint256 index_i,
        uint256 index_j
    ) external view returns (uint256 amountTokenBReceived, uint256 amountOut);

    /// @notice calculate the amount of an asset out for a given `amountVoltIn` of VOLT
    /// @dev indexes of tokens in curve pool must be known beforehand
    function getRedeemAmountOutMetaPool(
        uint256 amountVoltIn,
        IPegStabilityModule psm,
        address curvePool,
        uint256 index_i,
        uint256 index_j
    )
        external
        view
        returns (uint256 amountTokenAReceived, uint256 amountTokenBReceived);

    // ---------- State-Changing API ----------

    /// @notice Mint volt for stablecoins via curve plain pool
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
    ) external returns (uint256 amountOut);

    /// @notice Mint volt for stablecoins via curve metapool
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
    ) external returns (uint256 amountOut);

    /// @notice Redeems volt for stable via PSM then performs swap on a curve plain pool
    /// @param to, the address to send redeemed stablecoin to
    /// @param amountVoltIn, the amount of VOLT to deposit
    /// @param amountStableOut, the amount of stablecoin we expect from the PSM
    /// @param minAmountOut, the minimum amount of an asset expect to receive from curve
    /// @param psm, the PSM the router should redeem from
    /// @param curvePool, address of the curve pool
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
    ) external returns (uint256 amountOut);

    /// @notice Redeems volt for stable via PSM then performs swap on a curve metapool
    /// @param to, the address to send redeemed stablecoin to
    /// @param amountVoltIn, the amount of VOLT to deposit
    /// @param amountStableOut, the amount of stablecoin we expect from the PSM
    /// @param minAmountOut, the minimum amount of stablecoin expect to receive from curve
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
    ) external returns (uint256);

    /// @notice Approves different curve pools and PSMs to use the routers tokens
    /// @dev should only be callable by a governor
    /// @param tokenApprovals, the array of tokens and addresses to approve
    function setTokenApproval(TokenApproval[] memory tokenApprovals) external;
}
