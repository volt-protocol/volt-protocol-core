pragma solidity =0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPool} from "./IPool.sol";
import {IMplRewards} from "./IMplRewards.sol";
import {CoreRef} from "../../refs/CoreRef.sol";
import {PCVDeposit} from "../PCVDeposit.sol";

/// @notice PCV Deposit for Maple
/// Allows depositing only by privileged role to prevent lockup period being extended by griefers
contract MaplePCVDeposit is PCVDeposit {
    using SafeERC20 for IERC20;

    /// @notice reference to the Maple Pool where deposits and withdraws will originate
    IPool public immutable pool;

    /// @notice reference to the Maple Staking Rewards Contract
    IMplRewards public immutable mplRewards;

    /// @notice reference to the underlying token
    IERC20 public immutable token;

    /// @notice scaling factor
    uint256 public constant scalingFactor = 1e12;

    /// @notice fetch underlying asset by calling pool and getting liquidity asset
    /// @param _core reference to the Core contract
    /// @param _pool reference to the Maple Pool contract
    constructor(
        address _core,
        address _pool,
        address _mplRewards
    ) CoreRef(_core) {
        pool = IPool(_pool);
        token = IERC20(IPool(_pool).liquidityAsset());
        mplRewards = IMplRewards(_mplRewards);
    }

    /// @notice return the amount of funds this contract owns in Maple FDT's
    function balance() public view override returns (uint256) {
        return pool.balanceOf(address(this)) / scalingFactor;
    }

    /// @notice return the underlying token denomination for this deposit
    function balanceReportedIn() external view returns (address) {
        return address(token);
    }

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

        /// token withdraw
        uint256 scaledDepositAmount = amount * scalingFactor;
        pool.increaseCustodyAllowance(address(mplRewards), scaledDepositAmount);
        mplRewards.stake(scaledDepositAmount);

        emit Deposit(msg.sender, amount);
    }

    /// @notice function to start the cooldown process to withdraw
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
        mplRewards.withdraw(scaledWithdrawAmount); /// decreases allowance

        /// withdraw from the pool
        pool.withdraw(amount);
        token.safeTransfer(to, amount);

        emit Withdrawal(msg.sender, to, amount);
    }

    /// @notice withdraw all PCV from Maple
    function withdrawAll(address to) external onlyPCVController {
        uint256 amount = balance();
        mplRewards.exit(); /// unstakes from Maple reward contract and claims rewards
        pool.withdraw(amount); /// call pool and withdraw entire balance

        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        token.safeTransfer(to, tokenBalance);

        emit Withdrawal(msg.sender, to, tokenBalance);
    }
}
