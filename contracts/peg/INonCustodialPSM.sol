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
    // ----------- Governor or Admin Only State Changing API -----------

    /// @notice set the target for sending surplus reserves
    function setPCVDeposit(IPCVDeposit newTarget) external;

    // ----------- Getters -----------

    /// @notice the PCV deposit target to deposit and withdraw from
    function pcvDeposit() external view returns (IPCVDeposit);

    // ----------- Events -----------

    /// @notice event emitted when surplus target is updated
    event PCVDepositUpdate(IPCVDeposit oldTarget, IPCVDeposit newTarget);
}
