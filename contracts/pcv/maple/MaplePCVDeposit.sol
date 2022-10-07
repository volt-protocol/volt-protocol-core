pragma solidity =0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPool} from "./IPool.sol";
import {CoreRef} from "../../refs/CoreRef.sol";
import {PCVDeposit} from "../PCVDeposit.sol";
import {IMplRewards} from "./IMplRewards.sol";

/// @notice PCV Deposit for Maple
/// Allows depositing only by privileged role to prevent lockup period being extended by griefers

/// Can only deposit USDC in this MAPLE PCV deposit
contract MaplePCVDeposit is PCVDeposit {
    using SafeERC20 for IERC20;

    /// @notice reference to the Maple Pool where deposits and withdraws will originate
    IPool public immutable pool;

    /// @notice reference to the Maple Staking Rewards Contract
    IMplRewards public immutable mplRewards;

    /// @notice reference to the underlying token
    IERC20 public immutable token;

    /// @notice scaling factor for USDC
    /// @dev hardcoded to use USDC decimals as this is the only
    /// supplied asset Volt Protocol will support
    uint256 public constant scalingFactor = 1e12;

    /// @notice fetch underlying asset by calling pool and getting liquidity asset
    /// @param _core reference to the Core contract
    /// @param _pool Maple Pool contract
    /// @param _mplRewards Maple Rewards contract
    constructor(
        address _core,
        address _pool,
        address _mplRewards
    ) CoreRef(_core) {
        token = IERC20(IPool(_pool).liquidityAsset());
        /// enforce underlying token is USDC
        require(
            address(token) == 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            "MaplePCVDeposit: Underlying not USDC"
        );
        pool = IPool(_pool);
        mplRewards = IMplRewards(_mplRewards);
    }

    /// @notice return the amount of funds this contract owns in Maple FDT's
    /// without accounting for interest earned
    /// does not account for unrealized losses in the venue
    function balance() public view override returns (uint256) {
        uint256 rawBalance = pool.balanceOf(address(this)) +
            pool.accumulativeFundsOf(address(this)) -
            pool.recognizableLossesOf(address(this));
        return rawBalance / scalingFactor;
    }

    /// @notice return the underlying token denomination for this deposit
    function balanceReportedIn() external view returns (address) {
        return address(token);
    }

    /// ---------- Happy Path APIs ----------

    /// @notice deposit PCV into Maple.
    /// all deposits are subject to a minimum 90 day lockup,
    /// no op if 0 token balance
    /// deposits are then immediately staked to accrue MPL rewards
    /// only pcv controller can deposit, as this contract would be vulnerable
    /// to donation / griefing attacks if anyone could call deposit and extend lockup time
    function deposit() external onlyPCVController {
        uint256 amount = IERC20(token).balanceOf(address(this));
        if (amount == 0) {
            /// no op to prevent wasted gas
            return;
        }

        /// pool deposit
        token.approve(address(pool), amount);
        pool.deposit(amount);

        /// stake pool FDT for MPL rewards
        uint256 scaledDepositAmount = amount * scalingFactor;
        pool.increaseCustodyAllowance(address(mplRewards), scaledDepositAmount);
        mplRewards.stake(scaledDepositAmount);

        emit Deposit(msg.sender, amount);
    }

    /// @notice function to start the cooldown process to withdraw
    /// 1. lp lockup on deposit --> 90 days locked up and can't withdraw
    /// 2. cool down period, call intend to withdraw -->
    ///   must wait 10 days before withdraw after calling intend to withdraw function
    /// 3. after cool down and past the lockup period,
    ///    have 2 days to withdraw before cool down period restarts.
    function signalIntentToWithdraw() external onlyPCVController {
        pool.intendToWithdraw();
    }

    /// @notice function to cancel a withdraw
    /// should only be used to allow a transfer when doing a withdrawERC20 call
    function cancelWithdraw() external onlyPCVController {
        pool.cancelWithdraw();
    }

    /// @notice withdraw PCV from Maple, only callable by PCV controller
    /// @param to destination after funds are withdrawn from venue
    /// @param amount of PCV to withdraw from the venue
    function withdraw(address to, uint256 amount)
        external
        override
        onlyPCVController
    {
        uint256 scaledWithdrawAmount = amount * scalingFactor;

        mplRewards.getReward(); /// get MPL rewards
        /// this call will withdraw amount of principal requested, and then send
        /// over any accrued interest.
        /// expected behavior is that this contract
        /// receives either amount of USDC, or amount of USDC + interest accrued
        /// if lending losses were taken, receive less than amount
        mplRewards.withdraw(scaledWithdrawAmount); /// decreases allowance

        /// withdraw from the pool
        pool.withdraw(amount);

        /// withdraw min between balance and amount as losses could be sustained in venue
        /// causing less than amt to be withdrawn
        amount = Math.min(token.balanceOf(address(this)), amount);
        token.safeTransfer(to, amount);

        emit Withdrawal(msg.sender, to, amount);
    }

    /// @notice withdraw all PCV from Maple
    /// @param to destination after funds are withdrawn from venue
    function withdrawAll(address to) external onlyPCVController {
        uint256 amount = balance();
        mplRewards.exit(); /// unstakes from Maple reward contract and claims rewards
        /// this call will withdraw all principal,
        /// then send over any accrued interest.
        /// expected behavior is that this contract
        /// receives balance amount of USDC, or amount of USDC + interest accrued
        /// if lending losses were taken, receive less than amount
        pool.withdraw(amount); /// call pool and withdraw entire balance

        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        token.safeTransfer(to, tokenBalance);

        emit Withdrawal(msg.sender, to, tokenBalance);
    }

    /// @notice permissionless function to harvest rewards before withdraw
    function harvest() external {
        mplRewards.getReward();

        emit Harvest();
    }

    /// ---------- Sad Path APIs ----------

    /// @notice get rewards and unstake from rewards contract
    /// breaks functionality of happy path withdraw functions
    function exit() external onlyPCVController {
        mplRewards.exit();
    }

    /// @notice unstake from rewards contract without getting rewards
    /// breaks functionality of happy path withdraw functions
    function withdrawFromRewardsContract() external onlyPCVController {
        uint256 rewardsBalance = pool.balanceOf(address(this));
        mplRewards.withdraw(rewardsBalance);
    }

    /// @notice unstake from Pool FDT contract without getting rewards
    /// or unstaking from the reward contract.
    /// @param to destination after funds are withdrawn from venue
    /// @param amount of PCV to withdraw from the venue
    function withdrawFromPool(address to, uint256 amount)
        external
        onlyPCVController
    {
        pool.withdraw(amount);
        /// withdraw min between balance and amount as losses could be sustained in venue
        /// causing less than amt to be withdrawn
        amount = Math.min(token.balanceOf(address(this)), amount);
        token.safeTransfer(to, amount);
    }

    /// @notice struct to pack calldata and targets for an emergency action
    struct Call {
        address target;
        bytes callData;
    }

    /// @notice due to Maple's complexity, add this ability to be able
    /// to execute arbitrary calldata against arbitrary addresses.
    /// only callable by governor
    function emergencyAction(Call[] memory calls)
        external
        onlyGovernor
        returns (bytes[] memory returnData)
    {
        returnData = new bytes[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory returned) = calls[i].target.call(
                calls[i].callData
            );
            require(success);
            returnData[i] = returned;
        }
    }
}
