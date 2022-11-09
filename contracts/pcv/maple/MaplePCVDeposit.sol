// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {PCVDeposit} from "../PCVDeposit.sol";
import {CoreRefV2} from "../../refs/CoreRefV2.sol";
import {IPCVOracle} from "../../oracle/IPCVOracle.sol";

import {IMaplePool} from "./IMaplePool.sol";
import {IMapleRewards} from "./IMapleRewards.sol";

/// @notice PCV Deposit for Maple
/// Allows depositing only by privileged role to prevent lockup period being extended by griefers
/// Can only deposit USDC in this MAPLE PCV deposit due to the scaling factor being hardcoded
/// and underlying token is enforced as USDC.

/// @notice NEVER CONNECT THIS DEPOSIT INTO THE ALLOCATOR OR OTHER AUTOMATED PCV
/// SYSTEM. DEPOSITING LOCKS FUNDS FOR AN EXTENDED PERIOD OF TIME.

/// @dev On deposit, all Maple FDT tokens are immediately deposited into
/// the maple rewards contract that corresponds with the pool where funds are deposited.
/// On withdraw, the `signalIntentToWithdraw` function must be called.
/// In the withdraw function, the Maple FDT tokens are unstaked
/// from the rewards contract, this allows the underlying USDC to be withdrawn.
/// Maple withdraws have some interesting properties such as interest not being calculated into
/// the amount that is requested to be withdrawn. This means that asking to withdraw 100 USDC
/// could yield 101 USDC received in this PCV Deposit if interest has been earned, or it could
/// mean 95 USDC in this contract if losses are sustained in excess of interest earned.
/// Supporting these two situations adds additional code complexity, so unlike other PCV Deposits,
/// the amount withdrawn on this PCV Deposit is non-deterministic, so a sender could request 100
/// USDC out, and get another amount out. Dealing with these different pathways would add additional
/// code and complexity, so instead, Math.min(token.balanceOf(Address(this)), amountToWithdraw)
/// is used to determine the amount of tokens that will be sent out of the contract
/// after withdraw is called on the Maple market.
contract MaplePCVDeposit is PCVDeposit, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeCast for *;

    /// @notice emitted when the PCV Oracle address is updated
    event PCVOracleUpdated(address oldOracle, address newOracle);

    /// Mainnet USDC is used for accounting and deposit/withdraw
    /// @dev hardcoded to use USDC mainnet address as this is the only
    /// supplied asset Volt Protocol will support
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @notice scaling factor for USDC
    /// @dev hardcoded to use USDC decimals as this is the only
    /// supplied asset Volt Protocol will support
    uint256 private constant SCALING_FACTOR = 1e12;

    /// @notice reference to the Maple Pool where deposits and withdraws will originate
    address public immutable maplePool;

    /// @notice reference to the Maple Staking Rewards Contract
    address public immutable mapleRewards;

    /// @notice reference to the Maple token distributed as rewards
    address public immutable mapleToken;

    /// @notice track the last amount of PCV recorded in the contract
    /// this is always out of date, except when accrue() is called
    /// in the same block or transaction. This means the value is stale
    /// most of the time.
    uint256 public lastRecordedBalance;

    /// @notice reference to the PCV Oracle. Settable by governance
    /// if set, anytime PCV is updated, delta is sent in to update liquid
    /// amount of PCV held
    /// not set in the constructor
    address public pcvOracle;

    /// @param _core reference to the Core contract
    /// @param _maplePool Maple Pool contract
    /// @param _mapleRewards Maple Rewards contract
    /// @param _pcvOracle PCV Oracle to notify on balance changes
    constructor(
        address _core,
        address _maplePool,
        address _mapleRewards,
        address _pcvOracle
    ) CoreRefV2(_core) ReentrancyGuard() {
        maplePool = _maplePool;
        mapleRewards = _mapleRewards;
        mapleToken = IMapleRewards(_mapleRewards).rewardsToken();
        pcvOracle = _pcvOracle;
    }

    /// @notice return the amount of funds this contract owns in USDC
    /// accounting for interest earned
    /// and unrealized losses in the venue
    function balance() public view override returns (uint256) {
        // balanceOf returns a number with 18 decimals because Maple FDTs have 18 decimals
        // accumulativeFundsOf and recognizableLossesOf are expressed in the decimals
        // of the pool's underlying token (USDC), so they have 6 decimals, and we need to
        // normalize to combine these balances together.
        return
            IMaplePool(maplePool).balanceOf(address(this)) /
            SCALING_FACTOR +
            IMaplePool(maplePool).accumulativeFundsOf(address(this)) -
            IMaplePool(maplePool).recognizableLossesOf(address(this));
    }

    /// @notice return the underlying token denomination for this deposit
    function balanceReportedIn() external pure returns (address) {
        return USDC;
    }

    /// @notice set the pcv oracle address
    /// @param _pcvOracle new pcv oracle to reference
    function setPCVOracle(address _pcvOracle) external onlyGovernor {
        address oldOracle = pcvOracle;
        pcvOracle = _pcvOracle;

        _recordPNL();

        IPCVOracle(pcvOracle).updateIlliquidBalance(
            lastRecordedBalance.toInt256()
        );

        emit PCVOracleUpdated(oldOracle, _pcvOracle);
    }

    /// ---------- Happy Path APIs ----------

    /// @notice deposit PCV into Maple.
    /// deposits are subject to up to 30 days of lockup,
    /// weighted by the amount deposited and the deposit time.
    /// No op if 0 token balance.
    /// Deposits are then immediately staked to accrue MPL rewards.
    /// Only pcv controller can deposit, as this contract would be vulnerable
    /// to donation / griefing attacks if anyone could call deposit and extend lockup time.
    function deposit() external onlyPCVController {
        uint256 amount = IERC20(USDC).balanceOf(address(this));
        if (amount == 0) {
            /// no op to prevent wasted gas
            return;
        }

        int256 startingRecordedBalance = lastRecordedBalance.toInt256();

        /// ------ Effects ------

        /// compute profit from interest accrued and emit an event
        /// if any profits or losses are realized
        _recordPNL();

        lastRecordedBalance += amount;

        /// ------ Interactions ------

        /// pool deposit
        IERC20(USDC).approve(maplePool, amount);
        IMaplePool(maplePool).deposit(amount);

        /// stake pool FDT for MPL rewards
        uint256 scaledDepositAmount = amount * SCALING_FACTOR;
        IMaplePool(maplePool).increaseCustodyAllowance(
            mapleRewards,
            scaledDepositAmount
        );
        IMapleRewards(mapleRewards).stake(scaledDepositAmount);

        int256 endingRecordedBalance = lastRecordedBalance.toInt256();

        if (pcvOracle != address(0)) {
            IPCVOracle(pcvOracle).updateIlliquidBalance(
                endingRecordedBalance - startingRecordedBalance
            );
        }

        emit Deposit(msg.sender, amount);
    }

    /// @notice function to start the cooldown process to withdraw
    /// 1. lp lockup on deposit --> 90 days locked up and can't withdraw
    /// 2. cool down period, call intend to withdraw -->
    ///   must wait 10 days before withdraw after calling intend to withdraw function
    /// 3. after cool down and past the lockup period,
    ///    have 2 days to withdraw before cool down period restarts.
    function signalIntentToWithdraw() external onlyPCVController {
        IMaplePool(maplePool).intendToWithdraw();
    }

    /// @notice function to cancel a withdraw
    /// should only be used to allow a transfer when doing a withdrawERC20 call
    function cancelWithdraw() external onlyPCVController {
        IMaplePool(maplePool).cancelWithdraw();
    }

    /// @notice function that emits an event tracking profits and losses
    /// since the last contract interaction
    /// then writes the current amount of PCV tracked in this contract
    /// to lastRecordedBalance
    /// @return the amount deposited after adding accrued interest or realizing losses
    function accrue() external nonReentrant whenNotPaused returns (uint256) {
        int256 startingRecordedBalance = lastRecordedBalance.toInt256();

        _recordPNL(); // update deposit amount and fire harvest event

        int256 endingRecordedBalance = lastRecordedBalance.toInt256();

        if (pcvOracle != address(0)) {
            // if any amount of PCV is withdrawn and no gains, delta is negative
            IPCVOracle(pcvOracle).updateIlliquidBalance(
                endingRecordedBalance - startingRecordedBalance
            );
        }

        // return updated pcv amount
        // does not need a safe cast because balance is always positive
        return uint256(endingRecordedBalance);
    }

    /// @notice permissionless function to harvest rewards before withdraw
    function harvest() public nonReentrant whenNotPaused {
        uint256 preHarvestBalance = IERC20(mapleToken).balanceOf(address(this));

        IMapleRewards(mapleRewards).getReward();

        uint256 postHarvestBalance = IERC20(mapleToken).balanceOf(
            address(this)
        );

        emit Harvest(
            mapleToken,
            // no safecast needed because this will always be >= 0
            int256(postHarvestBalance - preHarvestBalance),
            block.timestamp
        );
    }

    /// @notice withdraw PCV from Maple, only callable by PCV controller
    /// @param to destination after funds are withdrawn from venue
    /// @param amount of PCV to withdraw from the venue
    function withdraw(address to, uint256 amount)
        external
        override
        onlyPCVController
    {
        /// Rewards

        harvest(); /// get rewards and fire MPL harvest event
        IMapleRewards(mapleRewards).withdraw(amount * SCALING_FACTOR); /// decreases allowance

        /// Principal

        int256 balanceBeforePnl = lastRecordedBalance.toInt256();

        _recordPNL(); /// update profit/losses and fire USDC harvest event

        uint256 lastRecordedBalanceAfterPnl = lastRecordedBalance;

        /// withdraw from the pool
        /// this call will withdraw amount of principal requested, and then send
        /// over any accrued interest.
        /// expected behavior is that this contract
        /// receives either amount of USDC, or amount of USDC + interest accrued
        /// if lending losses were taken, receive less than amount
        IMaplePool(maplePool).withdraw(amount);

        /// withdraw min between balance and amount as losses could be sustained in venue
        /// causing less than amt to be withdrawn
        uint256 amountToTransfer = Math.min(
            IERC20(USDC).balanceOf(address(this)),
            amount
        );
        IERC20(USDC).safeTransfer(to, amountToTransfer);

        uint256 balanceAfterTransfer = lastRecordedBalanceAfterPnl -
            amountToTransfer;
        lastRecordedBalance = balanceAfterTransfer;

        if (pcvOracle != address(0)) {
            /// if any amount of PCV is withdrawn and no gains, delta is negative
            IPCVOracle(pcvOracle).updateIlliquidBalance(
                balanceAfterTransfer.toInt256() - balanceBeforePnl
            );
        }

        emit Withdrawal(msg.sender, to, amountToTransfer);
    }

    /// @notice records how much profit or loss has been accrued
    /// since the last call and emits an event with all profit or loss received.
    /// Updates the lastRecordedBalance to include all realized profits or losses.
    function _recordPNL() private {
        /// ------ Check ------

        /// then get the current balance from the market
        uint256 currentBalance = balance();

        /// save gas if contract has no balance
        /// if cost basis is 0 and last recorded balance is 0
        /// there is no profit or loss to record and no reason
        /// to update lastRecordedBalance
        if (currentBalance == 0 && lastRecordedBalance == 0) {
            return;
        }

        /// currentBalance should always be greater than or equal to
        /// the deposited amount, except on the same block a deposit occurs, or a loss event in maple
        int256 profit = currentBalance.toInt256() -
            lastRecordedBalance.toInt256();

        /// ------ Effects ------

        /// record new deposited amount
        lastRecordedBalance = currentBalance;

        /// profit is in underlying token
        emit Harvest(USDC, profit, block.timestamp);
    }

    /// ---------- Sad Path APIs ----------

    /// Assume that using these functions will likely
    /// break all happy path functions
    /// Only use these function in an emergency situation

    /// -----------------------------------

    /// @notice get rewards and unstake from rewards contract
    /// breaks functionality of happy path withdraw functions
    function exitRewards() external onlyPCVController {
        IMapleRewards(mapleRewards).exit();
    }

    /// @notice unstake from rewards contract without getting rewards
    /// breaks functionality of happy path withdraw functions
    function withdrawFromRewardsContract() external onlyPCVController {
        uint256 rewardsBalance = IMaplePool(maplePool).balanceOf(address(this));
        IMapleRewards(mapleRewards).withdraw(rewardsBalance);
    }

    /// @notice unstake from Pool FDT contract without getting rewards
    /// or unstaking from the reward contract.
    /// @param to destination after funds are withdrawn from venue
    /// @param amount of PCV to withdraw from the venue
    function withdrawFromPool(address to, uint256 amount)
        external
        onlyPCVController
    {
        IMaplePool(maplePool).withdraw(amount);
        /// withdraw min between balance and amount as losses could be sustained in venue
        /// causing less than amt to be withdrawn
        uint256 amountToTransfer = Math.min(
            IERC20(USDC).balanceOf(address(this)),
            amount
        );
        IERC20(USDC).safeTransfer(to, amountToTransfer);

        emit Withdrawal(msg.sender, to, amountToTransfer);
    }
}
