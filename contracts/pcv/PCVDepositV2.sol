// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {IPCVDepositV2} from "./IPCVDepositV2.sol";

/// @title abstract contract for withdrawing ERC-20 tokens using a PCV Controller
/// @author Elliot Friedman
abstract contract PCVDepositV2 is IPCVDepositV2, CoreRefV2 {
    using SafeERC20 for IERC20;

    /// ------------------------------------------
    /// ------------- State Variables ------------
    /// ------------------------------------------

    /// @notice track the last amount of PCV recorded in the contract
    /// this is always out of date, except when accrue() is called
    /// in the same block or transaction. This means the value is stale
    /// most of the time.
    uint128 public lastRecordedBalance;

    /// @notice track the last amount of profits earned by the contract
    /// this is always out of date, except when accrue() is called
    /// in the same block or transaction. This means the value is stale
    /// most of the time.
    int128 public lastRecordedProfits;

    /// ------------- Internal Helpers -------------

    /// @notice records how much profit or loss has been accrued
    /// since the last call and emits an event with all profit or loss received.
    /// Updates the lastRecordedBalance to include all realized profits or losses.
    /// @return profit accumulated since last _recordPNL() call.
    function _recordPNL() internal returns (int256) {
        /// first accrue interest in the underlying venue
        _accrue();

        /// ------ Check ------

        /// then get the current balance from the market
        uint256 currentBalance = balance();

        /// save gas if contract has no balance
        /// if cost basis is 0 and last recorded balance is 0
        /// there is no profit or loss to record and no reason
        /// to update lastRecordedBalance
        if (currentBalance == 0 && lastRecordedBalance == 0) {
            return 0;
        }

        /// currentBalance should always be greater than or equal to
        /// the deposited amount, except on the same block a deposit occurs, or a loss event in morpho
        /// SLOAD
        uint128 _lastRecordedBalance = lastRecordedBalance;

        /// Compute profit
        int128 profit = int128(int256(currentBalance)) -
            int128(_lastRecordedBalance);

        int128 _lastRecordedProfits = lastRecordedProfits + profit;

        /// ------ Effects ------

        /// SSTORE: record new amounts
        lastRecordedProfits = _lastRecordedProfits;
        lastRecordedBalance = uint128(currentBalance);

        /// profit is in underlying token
        emit Harvest(token(), int256(profit), block.timestamp);

        return profit;
    }

    /// @notice helper function to avoid repeated code in withdraw and withdrawAll
    /// anytime this function is called it is by an external function in this smart contract
    /// with a reentrancy guard. This ensures lastRecordedBalance never desynchronizes.
    /// Morpho is assumed to be a loss-less venue. over the course of less than 1 block,
    /// it is possible to lose funds. However, after 1 block, deposits are expected to always
    /// be in profit at least with current interest rates around 0.8% natively on Compound,
    /// ignoring all COMP and Morpho rewards.
    /// @param to recipient of withdraw funds
    /// @param amount to withdraw
    /// @param recordPnl whether or not to record PnL. Set to false in withdrawAll
    /// as the function _recordPNL() is already called before _withdraw
    function _withdraw(
        address to,
        uint256 amount,
        bool recordPnl
    ) private returns (int256 profit) {
        /// ------ Effects ------

        if (recordPnl) {
            /// compute profit from interest accrued and emit a Harvest event
            profit = _recordPNL();
        }

        /// update last recorded balance amount
        /// if more than is owned is withdrawn, this line will revert
        /// this line of code is both a check, and an effect
        lastRecordedBalance -= uint128(amount);

        /// ------ Interactions ------

        _withdraw(amount);
        IERC20(token()).safeTransfer(to, amount);

        emit Withdrawal(msg.sender, to, amount);
    }

    /// ------------- Virtual Functions -------------

    /// @notice function to get balance in the underlying market.
    /// @return current balance of deposit
    function balance() public view virtual override returns (uint256);

    /// @dev function to get the underlying token.
    function token() public view virtual override returns (address);

    /// @dev function to accrue in the underlying market.
    function _accrue() internal virtual;

    /// @dev function to accrue in the underlying market.
    function _withdraw(uint256 amount) internal virtual;
}
