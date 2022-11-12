// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPCVDeposit} from "../pcv/IPCVDeposit.sol";

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

    /// @notice redeem `amountVoltIn` VOLT for `amountOut` underlying tokens and send to address `to`
    /// @dev see getRedeemAmountOut() to pre-calculate amount out
    function redeem(
        address to,
        uint256 amountVoltIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut);

    // ----------- Governor or Admin Only State Changing API -----------

    /// @notice set the target for sending surplus reserves
    function setPCVDeposit(IPCVDeposit newTarget) external;

    /// @notice sets the floor price in BP
    function setOracleFloorPrice(uint128 newFloor) external;

    /// @notice sets the ceiling price in BP
    function setOracleCeilingPrice(uint128 newCeiling) external;

    // ----------- Getters -----------

    /// @notice get the floor price in basis points
    function floor() external view returns (uint128);

    /// @notice get the ceiling price in basis points
    function ceiling() external view returns (uint128);

    /// @notice calculate the amount of underlying out for a given `amountVoltIn` of VOLT
    function getRedeemAmountOut(
        uint256 amountVoltIn
    ) external view returns (uint256 amountOut);

    /// @notice the underlying token exchanged for VOLT
    function underlyingToken() external view returns (IERC20);

    /// @notice the PCV deposit target to deposit and withdraw from
    function pcvDeposit() external view returns (IPCVDeposit);

    // ----------- Events -----------

    /// @notice event emitted when surplus target is updated
    event PCVDepositUpdate(IPCVDeposit oldTarget, IPCVDeposit newTarget);

    /// @notice event emitted upon a redemption
    event Redeem(address to, uint256 amountVoltIn, uint256 amountAssetOut);

    /// @notice event emitted when minimum floor price is updated
    event OracleFloorUpdate(uint128 oldFloor, uint128 newFloor);

    /// @notice event emitted when maximum ceiling price is updated
    event OracleCeilingUpdate(uint128 oldCeiling, uint128 newCeiling);
}
