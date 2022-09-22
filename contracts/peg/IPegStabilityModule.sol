// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../pcv/IPCVDeposit.sol";

/**
 * @title Volt Peg Stability Module
 * @author Volt, Fei Protocol
 * @notice  The Volt PSM is a contract which holds a reserve of assets in order to exchange VOLT at its current peg price with a fee.
 * `mint()` - buy VOLT at peg price
 * `redeem()` - sell VOLT back the same peg price
 * price rounds down in favor of the protoocol to avoid any instant arbs
 *
 * The contract is a
 * PCVDeposit - to track reserves
 * OracleRef - to determine price of VOLT and underlying, and
 *
 * Inspired by MakerDAO and FEI PSM
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

    /// @notice calculate the amount of VOLT out for a given `amountIn` of underlying
    function getMintAmountOut(uint256 amountIn)
        external
        view
        returns (uint256 amountVoltOut);

    /// @notice calculate the amount of underlying out for a given `amountVoltIn` of VOLT
    function getRedeemAmountOut(uint256 amountVoltIn)
        external
        view
        returns (uint256 amountOut);

    /// @notice the underlying token exchanged for VOLT
    function underlyingToken() external view returns (IERC20);

    /// @notice the PCV deposit target to send all proceeds from minting
    /// and the pull all required funds for redeeming
    function pcvDeposit() external view returns (IPCVDeposit);

    // ----------- Events -----------

    /// @notice event emitted upon a redemption
    event Redeem(address to, uint256 amountVoltIn, uint256 amountAssetOut);

    /// @notice event emitted when VOLT gets minted
    event Mint(address to, uint256 amountIn, uint256 amountVoltOut);
}
