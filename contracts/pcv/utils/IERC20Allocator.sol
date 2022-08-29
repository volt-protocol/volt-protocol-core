pragma solidity =0.8.13;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {PCVDepositV2} from "./../PCVDepositV2.sol";
import {Timed} from "./../../utils/Timed.sol";
import {CoreRef} from "./../../refs/CoreRef.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Contract to remove all excess funds past a certain threshold from a smart contract
/// used to allocate funds from a PSM to a yield venue so that liquid reserves are minimized
/// This contract should never hold PCV, however it is a PCV Deposit, so if tokens get sent to it,
/// they can still be recovered.
/// @author Volt Protocol
interface IERC20Allocator {
    /// @notice event emitted when tokens are sent to the pushTarget from the pullTarget
    event Skimmed(uint256 amount);

    /// @notice event emitted when tokens are sent to the pullTarget from the pushTarget
    event Dripped(uint256 amount);

    /// @notice event emitted when new pull threshold is set
    event TargetBalanceUpdate(uint256 oldThreshold, uint256 newThreshold);

    /// @notice target address to send excess tokens
    function pcvDeposit() external view returns (address);

    /// @notice target address to pull excess tokens from
    function psm() external view returns (address);

    /// @notice target token address to send
    function token() external view returns (address);

    /// @notice only pull if and only if balance of target is greater than pullThreshold
    function targetBalance() external view returns (uint256);

    /// @notice pull ERC20 tokens from pull target and send to push target
    /// if and only if the amount of tokens held in the contract is above
    /// the threshold.
    function skim() external;

    /// @notice function that returns whether the amount of tokens held
    /// are above the target and funds should flow from PSM -> PCV Deposit
    function checkSkimCondition() external view returns (bool);

    /// @notice function that returns whether the amount of tokens held
    /// are below the target and funds should flow from PCV Deposit -> PSM
    function checkDripCondition() external view returns (bool);

    /// @notice set the pull threshold
    /// @param newPullThreshold the new amount over which any excess funds will be sent
    function setTargetBalance(uint256 newPullThreshold) external;
}
