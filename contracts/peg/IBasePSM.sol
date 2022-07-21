// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../pcv/IPCVDeposit.sol";

/**
 * @title Volt Base Peg Stability Module
 * @author Volt Protocol
 * @notice  The Volt PSM is a contract which holds a reserve of assets in order to exchange VOLT for underlying assets.
 * `mint()` - buy VOLT with underlying tokens
 * `redeem()` - sell VOLT back for underlying tokens
 *
 * The contract has a reservesThreshold() of underlying meant to stand ready for redemptions. Any surplus reserves can be sent into the PCV using `allocateSurplus()`
 *
 * The contract is a
 * PCVDeposit - to track reserves
 *
 */
interface IBasePSM {
    /// @notice struct for passing constructor parameters related to OracleRef
    struct OracleParams {
        address coreAddress;
        address oracleAddress;
        address backupOracle;
        int256 decimalsNormalizer;
        bool doInvert;
    }

    // ----------- Public State Changing API -----------

    /// @notice mint `amountVoltOut` VOLT to address `to` for `amountIn` underlying tokens
    /// @dev see getMintAmountOut() to pre-calculate amount out
    function mint(
        address to,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountVoltOut);

    /// @notice redeem `amountVoltIn` VOLT for `amountOut` underlying tokens and send to address `to`
    /// @dev see getRedeemAmountOut() to pre-calculate amount out
    function redeem(
        address to,
        uint256 amountVoltIn,
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

    /// @notice the maximum mint amount out
    function getMaxMintAmountOut() external view returns (uint256);

    /// @notice the underlying token exchanged for VOLT
    function underlyingToken() external view returns (IERC20);

    // ----------- Events -----------

    /// @notice event emitted upon a redemption
    event Redeem(address to, uint256 amountVoltIn, uint256 amountAssetOut);

    /// @notice event emitted when VOLT gets minted
    event Mint(address to, uint256 amountIn, uint256 amountVoltOut);
}
