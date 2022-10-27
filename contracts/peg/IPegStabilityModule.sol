// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPCVDeposit} from "../pcv/IPCVDeposit.sol";

/**
 * @title Fei Peg Stability Module
 * @author Fei Protocol
 * @notice  The Fei PSM is a contract which holds a reserve of assets in order to exchange FEI at $1 of underlying assets with a fee.
 * `mint()` - buy FEI for $1 of underlying tokens
 * `redeem()` - sell FEI back for $1 of the same
 *
 * The contract has a reservesThreshold() of underlying meant to stand ready for redemptions. Any surplus reserves can be sent into the PCV using `allocateSurplus()`
 *
 * The contract is a
 * PCVDeposit - to track reserves
 * OracleRef - to determine price of underlying, and
 * RateLimitedMinter - to stop infinite mints and related issues (but this is in the implementation due to inheritance-linearization difficulties)
 *
 * Inspired by MakerDAO PSM, code written without reference
 */
interface IPegStabilityModule {
    // ----------- Public State Changing API -----------

    /// @notice mint `amountFeiOut` FEI to address `to` for `amountIn` underlying tokens
    /// @dev see getMintAmountOut() to pre-calculate amount out
    function mint(
        address to,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountFeiOut);

    /// @notice redeem `amountFeiIn` FEI for `amountOut` underlying tokens and send to address `to`
    /// @dev see getRedeemAmountOut() to pre-calculate amount out
    function redeem(
        address to,
        uint256 amountFeiIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut);

    // ----------- Getters -----------

    /// @notice calculate the amount of FEI out for a given `amountIn` of underlying
    function getMintAmountOut(uint256 amountIn)
        external
        view
        returns (uint256 amountFeiOut);

    /// @notice calculate the amount of underlying out for a given `amountFeiIn` of FEI
    function getRedeemAmountOut(uint256 amountFeiIn)
        external
        view
        returns (uint256 amountOut);

    /// @notice the maximum mint amount out
    function getMaxMintAmountOut() external view returns (uint256);

    /// @notice the underlying token exchanged for FEI
    function underlyingToken() external view returns (IERC20);

    // ----------- Events -----------

    /// @notice event emitted when excess PCV is allocated
    event AllocateSurplus(address indexed caller, uint256 amount);

    /// @notice event emitted upon a redemption
    event Redeem(address to, uint256 amountFeiIn, uint256 amountAssetOut);

    /// @notice event emitted when fei gets minted
    event Mint(address to, uint256 amountIn, uint256 amountFeiOut);
}
