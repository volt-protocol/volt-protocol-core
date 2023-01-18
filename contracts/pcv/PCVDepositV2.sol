// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {IPCVDepositV2} from "./IPCVDepositV2.sol";

/// @title abstract contract for withdrawing ERC-20 tokens using a PCV Controller
/// @author Elliot Friedman
abstract contract PCVDepositV2 is IPCVDepositV2, CoreRefV2 {
    using SafeERC20 for IERC20;
    using SafeCast for *;

    /// @notice reference to underlying token
    address public immutable override rewardToken;

    /// @notice reference to underlying token
    address public immutable override token;

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

    constructor(address _token, address _rewardToken) {
        token = _token;
        rewardToken = _rewardToken;
    }

    /// ------------------------------------------
    /// ----------- Permissionless API -----------
    /// ------------------------------------------

    /// @notice deposit ERC-20 tokens to Morpho-Compound
    /// non-reentrant to block malicious reentrant state changes
    /// to the lastRecordedBalance variable
    function deposit() public whenNotPaused globalLock(2) {
        /// ------ Check ------

        uint256 amount = IERC20(token).balanceOf(address(this));
        if (amount == 0) {
            /// no op to prevent revert on empty deposit
            return;
        }

        int256 startingRecordedBalance = lastRecordedBalance.toInt256();

        /// ------ Effects ------

        /// compute profit from interest accrued and emit an event
        /// if any profits or losses are realized
        int256 profit = _recordPNL();

        /// increment tracked recorded amount
        /// this will be off by a hair, after a single block
        /// negative delta turns to positive delta (assuming no loss).
        lastRecordedBalance += uint128(amount);

        /// ------ Interactions ------

        /// approval and deposit into underlying venue
        _supply(amount);

        /// ------ Update Internal Accounting ------

        int256 endingRecordedBalance = balance().toInt256();

        _liquidPcvOracleHook(
            endingRecordedBalance - startingRecordedBalance,
            profit
        );

        emit Deposit(msg.sender, amount);
    }

    /// @notice claim COMP rewards for supplying to Morpho.
    /// Does not require reentrancy lock as no smart contract state is mutated
    /// in this function.
    function harvest() external globalLock(2) {
        uint256 claimedAmount = _claim();

        emit Harvest(rewardToken, int256(claimedAmount), block.timestamp);
    }

    /// @notice function that emits an event tracking profits and losses
    /// since the last contract interaction
    /// then writes the current amount of PCV tracked in this contract
    /// to lastRecordedBalance
    /// @return the amount deposited after adding accrued interest or realizing losses
    function accrue() external globalLock(2) whenNotPaused returns (uint256) {
        int256 profit = _recordPNL(); /// update deposit amount and fire harvest event

        /// if any amount of PCV is withdrawn and no gains, delta is negative
        _liquidPcvOracleHook(profit, profit);

        return lastRecordedBalance; /// return updated pcv amount
    }

    /// ------------------------------------------
    /// ------------ Permissioned API ------------
    /// ------------------------------------------

    /// @notice withdraw tokens from the PCV allocation
    /// non-reentrant as state changes and external calls are made
    /// @param to the address PCV will be sent to
    /// @param amount of tokens withdrawn
    function withdraw(
        address to,
        uint256 amount
    ) external onlyPCVController globalLock(2) {
        int256 profit = _withdraw(to, amount, true);

        /// if any amount of PCV is withdrawn and no gains, delta is negative
        _liquidPcvOracleHook(-(amount.toInt256()) + profit, profit);
    }

    /// @notice withdraw all tokens from Morpho
    /// non-reentrant as state changes and external calls are made
    /// @param to the address PCV will be sent to
    function withdrawAll(address to) external onlyPCVController globalLock(2) {
        /// compute profit from interest accrued and emit an event
        int256 profit = _recordPNL();

        int256 recordedBalance = lastRecordedBalance.toInt256();

        /// withdraw last recorded amount as this was updated in record pnl
        _withdraw(to, lastRecordedBalance, false);

        /// all PCV withdrawn, send call in with amount withdrawn negative if any amount is withdrawn
        _liquidPcvOracleHook(-recordedBalance, profit);
    }

    /// @notice withdraw ERC20 from the contract
    /// @param tokenAddress address of the ERC20 to send
    /// @param to address destination of the ERC20
    /// @param amount quantity of ERC20 to send
    /// Calling this function will lead to incorrect
    /// accounting in a PCV deposit that tracks
    /// profits and or last recorded balance.
    /// If a deposit records PNL, only use this
    /// function in an emergency.
    function withdrawERC20(
        address tokenAddress,
        address to,
        uint256 amount
    ) public virtual override onlyPCVController {
        IERC20(tokenAddress).safeTransfer(to, amount);
        emit WithdrawERC20(msg.sender, tokenAddress, to, amount);
    }

    /// ------------- Internal Helpers -------------

    /// @notice records how much profit or loss has been accrued
    /// since the last call and emits an event with all profit or loss received.
    /// Updates the lastRecordedBalance to include all realized profits or losses.
    /// @return profit accumulated since last _recordPNL() call.
    function _recordPNL() internal returns (int256) {
        /// first accrue interest in the underlying venue
        _accrueUnderlying();

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
        emit Harvest(token, int256(profit), block.timestamp);

        return profit;
    }

    /// @notice helper avoid repeated code in withdraw and withdrawAll
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

        /// remove funds from underlying venue
        _withdrawAndTransfer(amount, to);

        /// transfer funds to recipient
        IERC20(token).safeTransfer(to, amount);

        emit Withdrawal(msg.sender, to, amount);
    }

    /// ------------- Virtual Functions -------------

    /// @notice get balance in the underlying market.
    /// @return current balance of deposit
    function balance() public view virtual override returns (uint256);

    /// @dev accrue interest in the underlying market.
    function _accrueUnderlying() internal virtual;

    /// @dev withdraw from the underlying market.
    function _withdrawAndTransfer(uint256 amount, address to) internal virtual;

    /// @dev deposit in the underlying market.
    function _supply(uint256 amount) internal virtual;

    /// @dev claim rewards from the underlying market.
    /// returns amount of reward tokens claimed
    function _claim() internal virtual returns (uint256);
}
