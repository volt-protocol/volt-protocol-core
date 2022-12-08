// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ILens} from "./ILens.sol";
import {ICToken} from "./ICompound.sol";
import {IMorpho} from "./IMorpho.sol";
import {CoreRefV2} from "../../refs/CoreRefV2.sol";
import {Constants} from "../../Constants.sol";
import {PCVDeposit} from "../PCVDeposit.sol";

/// @notice PCV Deposit for Morpho-Compound V2.
/// Implements the PCV Deposit interface to deposit and withdraw funds in Morpho
/// Liquidity profile of Morpho for this deposit is fully liquid for USDC and DAI
/// because the incentivized rates are higher than the P2P rate.
/// Only for depositing USDC and DAI. USDT is not in scope.
/// @dev approves the Morpho Deposit to spend this PCV deposit's token,
/// and then calls supply on Morpho, which pulls the underlying token to Morpho,
/// drawing down on the approved amount to be spent,
/// and then giving this PCV Deposit credits on Morpho in exchange for the underlying
/// @dev PCV Guardian functions withdrawERC20ToSafeAddress and withdrawAllERC20ToSafeAddress
/// will not work with removing Morpho Tokens on the Morpho PCV Deposit because Morpho
/// has no concept of mTokens. This means if the contract is paused, or an issue is
/// surfaced in Morpho and liquidity is locked, Volt will need to rely on social
/// coordination with the Morpho team to recover funds.
/// @dev Depositing and withdrawing in a single block will cause a very small loss
/// of funds, less than a pip. The way to not realize this loss is by depositing and
/// then withdrawing at least 1 block later. That way, interest accrues.
/// This is not a Morpho specific issue. Compound rounds in the protocol's favor.
/// The issue is caused by constraints inherent to solidity and the EVM.
/// There are no floating point numbers, this means there is precision loss,
/// and protocol engineers are forced to choose who to round in favor of.
/// Engineers must round in favor of the protocol to avoid deposits of 0 giving
/// the user a balance.
contract MorphoCompoundPCVDeposit is PCVDeposit {
    using SafeERC20 for IERC20;
    using SafeCast for *;

    /// ------------------------------------------
    /// ---------- Immutables/Constant -----------
    /// ------------------------------------------

    /// @notice reference to the COMP governance token
    /// used for recording COMP rewards type in Harvest event
    address public constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;

    /// @notice reference to the lens contract for morpho-compound v2
    address public immutable lens;

    /// @notice reference to the morpho-compound v2 market
    address public immutable morpho;

    /// @notice reference to underlying token
    address public immutable token;

    /// @notice cToken in compound this deposit tracks
    /// used to inform morpho about the desired market to supply liquidity
    address public immutable cToken;

    /// ------------------------------------------
    /// ------------- State Variables -------------
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

    /// @param _core reference to the core contract
    /// @param _cToken cToken this deposit references
    /// @param _underlying Token denomination of this deposit
    /// @param _morpho reference to the morpho-compound v2 market
    /// @param _lens reference to the morpho-compound v2 lens
    constructor(
        address _core,
        address _cToken,
        address _underlying,
        address _morpho,
        address _lens
    ) CoreRefV2(_core) {
        if (_underlying != address(Constants.WETH)) {
            require(
                ICToken(_cToken).underlying() == _underlying,
                "MorphoCompoundPCVDeposit: Underlying mismatch"
            );
        }
        cToken = _cToken;
        token = _underlying;
        morpho = _morpho;
        lens = _lens;
    }

    /// ------------------------------------------
    /// ------------------ Views -----------------
    /// ------------------------------------------

    /// @notice Returns the distribution of assets supplied by this contract through Morpho-Compound.
    /// @return sum of suppliedP2P and suppliedOnPool for the given CToken
    function balance() public view override returns (uint256) {
        (, , uint256 totalSupplied) = ILens(lens).getCurrentSupplyBalanceInOf(
            cToken,
            address(this)
        );

        return totalSupplied;
    }

    /// @notice returns the underlying token of this deposit
    function balanceReportedIn() external view returns (address) {
        return token;
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

        IERC20(token).approve(address(morpho), amount);
        IMorpho(morpho).supply(
            cToken, /// cToken to supply liquidity to
            address(this), /// the address of the user you want to supply on behalf of
            amount
        );

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
        address[] memory cTokens = new address[](1);
        cTokens[0] = cToken;

        /// set swap comp to morpho flag false to claim comp rewards
        uint256 claimedAmount = IMorpho(morpho).claimRewards(cTokens, false);

        emit Harvest(COMP, int256(claimedAmount), block.timestamp);
    }

    /// @notice function that emits an event tracking profits and losses
    /// since the last contract interaction
    /// then writes the current amount of PCV tracked in this contract
    /// to lastRecordedBalance
    /// @return the amount deposited after adding accrued interest or realizing losses
    function accrue() external globalLock(2) whenNotPaused returns (uint256) {
        int256 startingRecordedBalance = lastRecordedBalance.toInt256();

        int256 profit = _recordPNL(); /// update deposit amount and fire harvest event

        uint256 endingRecordedBalance = lastRecordedBalance;

        /// if any amount of PCV is withdrawn and no gains, delta is negative
        _liquidPcvOracleHook(
            endingRecordedBalance.toInt256() - startingRecordedBalance,
            profit
        );

        return endingRecordedBalance; /// return updated pcv amount
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
        int256 startingRecordedBalance = lastRecordedBalance.toInt256();

        int256 profit = _withdraw(to, amount, true);

        int256 endingRecordedBalance = lastRecordedBalance.toInt256();

        /// if any amount of PCV is withdrawn and no gains, delta is negative
        _liquidPcvOracleHook(
            endingRecordedBalance - startingRecordedBalance,
            profit
        );
    }

    /// @notice withdraw all tokens from Morpho
    /// non-reentrant as state changes and external calls are made
    /// @param to the address PCV will be sent to
    function withdrawAll(address to) external onlyPCVController globalLock(2) {
        int256 startingRecordedBalance = lastRecordedBalance.toInt256();

        /// compute profit from interest accrued and emit an event
        int256 profit = _recordPNL();

        /// withdraw last recorded amount as this was updated in record pnl
        _withdraw(to, lastRecordedBalance, false);

        int256 endingRecordedBalance = lastRecordedBalance.toInt256();

        /// all PCV withdrawn, send call in with amount withdrawn negative if any amount is withdrawn
        _liquidPcvOracleHook(
            endingRecordedBalance - startingRecordedBalance,
            profit
        );
    }

    /// ------------------------------------------
    /// ------------- Helper Methods -------------
    /// ------------------------------------------

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

        IMorpho(morpho).withdraw(cToken, amount);
        IERC20(token).safeTransfer(to, amount);

        emit Withdrawal(msg.sender, to, amount);
    }

    /// @notice records how much profit or loss has been accrued
    /// since the last call and emits an event with all profit or loss received.
    /// Updates the lastRecordedBalance to include all realized profits or losses.
    /// @return profit accumulated since last _recordPNL() call.
    function _recordPNL() private returns (int256) {
        /// first accrue interest in Compound and Morpho
        IMorpho(morpho).updateP2PIndexes(cToken);

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
        int128 _lastRecordedProfits = lastRecordedProfits;

        /// Compute profit
        int128 profit = int128(int256(currentBalance)) -
            int128(_lastRecordedBalance);

        /// ------ Effects ------

        /// SSTORE: record new amounts
        lastRecordedProfits = _lastRecordedProfits + profit;
        lastRecordedBalance = uint128(currentBalance);

        /// profit is in underlying token
        emit Harvest(token, int256(profit), block.timestamp);

        return profit;
    }
}
