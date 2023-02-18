// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPCVDepositV2} from "@voltprotocol/pcv/IPCVDepositV2.sol";

/**
 * @title Volt Peg Stability Module
 * @author Volt Protocol
 * @notice  The Volt PSM is a contract which holds a reserve
 * of assets in order to exchange Volt at the current market
 * price against external assets with no fees.
 * `redeem()` - sell Volt back in exchange for underlying tokens
 *
 * The contract is a
 * PCVDeposit - to be able to withdraw PCV and
 * OracleRef - to determine price of underlying
 *
 * Inspired by Tribe DAO and MakerDAO PSM
 */
interface INonCustodialPSM {
    // ----------- Public State Changing API -----------

    /// @notice function to buy VOLT for an underlying asset
    /// This contract has no minting functionality, so the max
    /// amount of Volt that can be purchased is the Volt balance in the contract
    /// @dev does not require non-reentrant modifier because this contract
    /// stores no state. Even if USDC, DAI or any other token this contract uses
    /// had an after transfer hook, calling mint or redeem in a reentrant fashion
    /// would not allow any theft of funds, it would simply build up a call stack
    /// of orders that would need to be executed.
    /// @param to recipient of the Volt
    /// @param amountIn amount of underlying tokens used to purchase Volt
    /// @param minAmountOut minimum amount of Volt recipient to receive
    function mint(
        address to,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountVoltOut);

    /// @notice function to redeem VOLT for an underlying asset
    /// @dev does not require non-reentrant modifier because this contract
    /// stores no state. Even if USDC, DAI or any other token this contract uses
    /// had an after transfer hook, calling mint or redeem in a reentrant fashion
    /// would not allow any theft of funds, it would simply build up a call stack
    /// of orders that would need to be executed.
    /// @param to recipient of underlying tokens
    /// @param amountVoltIn amount of volt to sell
    /// @param minAmountOut of underlying tokens sent to recipient
    function redeem(
        address to,
        uint256 amountVoltIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut);

    // ----------- Governor or admin only state changing api -----------

    /// @notice sets the floor price in BP
    function setOracleFloorPrice(uint128 newFloor) external;

    /// @notice sets the ceiling price in BP
    function setOracleCeilingPrice(uint128 newCeiling) external;

    /// @notice set the target for sending proceeds and 
    function setPCVDeposit(IPCVDepositV2 newTarget) external;

    // ----------- Getters -----------

    /// @notice get the floor price in basis points
    function floor() external view returns (uint128);

    /// @notice get the ceiling price in basis points
    function ceiling() external view returns (uint128);

    /// @notice return wether the current oracle price is valid or not
    function isPriceValid() external view returns (bool);

    /// @notice calculate the amount of Volt out for a given `amountIn` of underlying
    function getMintAmountOut(
        uint256 amountIn
    ) external view returns (uint256 amountVoltOut);

    /// @notice calculate the amount of underlying out for a given `amountVoltIn` of Volt
    function getRedeemAmountOut(
        uint256 amountVoltIn
    ) external view returns (uint256 amountOut);

    /// @notice the underlying token exchanged for Volt
    function underlyingToken() external view returns (IERC20);

    /// @notice returns the maximum amount of Volt that can be redeemed
    /// Custodial PSM checks with the current PSM balance
    /// Non Custodial PSM checks with the current PCV Deposit balance and the Global System Exit Rate Limit Buffer
    function getMaxRedeemAmountIn() external view returns (uint256);

    /// @notice the PCV deposit target to deposit and withdraw from
    function pcvDeposit() external view returns (IPCVDepositV2);

    // ----------- Events -----------

    /// @notice event emitted when surplus target is updated
    event PCVDepositUpdate(address oldTarget, address newTarget);

    /// @notice event emitted upon a redemption
    event Redeem(address to, uint256 amountVoltIn, uint256 amountAssetOut);

    /// @notice event emitted when Volt gets minted
    event Mint(address to, uint256 amountIn, uint256 amountVoltOut);

    /// @notice event emitted when minimum floor price is updated
    event OracleFloorUpdate(uint128 oldFloor, uint128 newFloor);

    /// @notice event emitted when maximum ceiling price is updated
    event OracleCeilingUpdate(uint128 oldCeiling, uint128 newCeiling);
}
