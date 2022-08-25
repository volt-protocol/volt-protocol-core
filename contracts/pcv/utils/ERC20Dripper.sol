pragma solidity ^0.8.4;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {PCVDepositV2} from "./../PCVDepositV2.sol";
import {Timed} from "./../../utils/Timed.sol";
import {CoreRef} from "./../../refs/CoreRef.sol";

/// @notice smart contract
contract ERC20Dripper is PCVDepositV2, Timed {
    using Address for address payable;

    /// @notice event emitted when tokens are dripped
    event Dripped(uint256 amount);

    /// @notice deposit to pull funds from
    PCVDepositV2 public immutable pcvDeposit;

    /// @notice target address to drip tokens to
    address public immutable target;

    /// @notice target token address to send
    address public immutable token;

    /// @notice only drip if and only if balance of target is less than dripThreshold
    uint256 public dripThreshold;

    /// @notice ERC20 PCV Dripper constructor
    /// @param _core Fei Core for reference
    /// @param _target address to drip to
    /// @param _frequency frequency of dripping
    /// @param _dripThreshold balance targeted in target
    /// @param _pcvDeposit pcv deposit to pull funds from
    constructor(
        address _core,
        address _target,
        uint256 _frequency,
        uint256 _dripThreshold,
        PCVDepositV2 _pcvDeposit
    ) CoreRef(_core) Timed(_frequency) {
        target = _target;
        dripThreshold = _dripThreshold;
        pcvDeposit = _pcvDeposit;
        token = _pcvDeposit.balanceReportedIn();

        // start timer
        _initTimed();
    }

    /// @notice drip ERC20 tokens to target by pulling from a PCV deposit
    function drip() external afterTime whenNotPaused {
        // reset timer
        _initTimed();

        require(checkCondition(), "ERC20Dripper: condition not met");

        uint256 targetBalance = IERC20(token).balanceOf(target);
        /// drip min between target drip amount and pcv deposit being pulled from
        /// to prevent edge cases when a venue runs out of liquidity
        uint256 amountToDrip = Math.min(
            dripThreshold - targetBalance,
            pcvDeposit.balance()
        );

        // drip amount to target so that it has dripThreshold amount of tokens
        pcvDeposit.withdraw(target, amountToDrip);
        emit Dripped(amountToDrip);
    }

    /// @notice function that returns whether the amount of tokens held
    /// is less than the threshold
    function checkCondition() public view returns (bool) {
        return IERC20(token).balanceOf(target) < dripThreshold;
    }

    /// @notice withdraw tokens from the PCV allocation
    /// @param amountUnderlying of tokens withdrawn
    /// @param to the address to send PCV to
    function withdraw(address to, uint256 amountUnderlying)
        external
        override
        onlyPCVController
    {
        _withdrawERC20(address(token), to, amountUnderlying);
    }

    /// @notice no-op
    function deposit() external override {}

    /// @notice returns total balance of PCV in the Deposit
    function balance() public view override returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @notice display the related token of the balance reported
    function balanceReportedIn() public view override returns (address) {
        return token;
    }
}
