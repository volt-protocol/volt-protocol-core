pragma solidity =0.8.13;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PCVDepositV2} from "./../PCVDepositV2.sol";
import {Timed} from "./../../utils/Timed.sol";
import {CoreRef} from "./../../refs/CoreRef.sol";
import {IERC20Allocator} from "./IERC20Allocator.sol";
import {RateLimitedV2} from "./../../utils/RateLimitedV2.sol";

/// @notice Contract to remove all excess funds past a target balance from a smart contract
/// and to add funds to that same smart contract when it is under the target balance.
/// First application is allocating funds from a PSM to a yield venue so that liquid reserves are minimized.
/// This contract should never hold PCV, however it is a PCV Deposit, so if tokens get sent to it,
/// they can still be recovered.
/// @author Volt Protocol
contract ERC20Allocator is
    IERC20Allocator,
    CoreRef,
    PCVDepositV2,
    RateLimitedV2
{
    using Address for address payable;

    /// @notice target address to send excess tokens, will be a Compound PCV Deposit
    address public immutable pcvDeposit;

    /// @notice target address to pull excess tokens from, will be a PSM
    address public immutable psm;

    /// @notice target token address to send
    address public immutable token;

    /// @notice only pull if and only if balance of target is greater than targetBalance
    /// only push if and only if balance of target is less than targetBalance
    uint256 public targetBalance;

    /// @notice ERC20 PCV Puller constructor
    /// @param _core Volt Core for reference
    /// @param _pcvDeposit address to push funds
    /// @param _psm address to pull from
    /// @param _targetBalance amount over which any excess gets sent to the target
    /// @param _token ERC20 to pull
    /// @param _maxRateLimitPerSecond maximum rate limit per second that governance can set
    /// @param _rateLimitPerSecond starting rate limit per second
    /// @param _bufferCap cap on buffer size for this rate limited instance
    constructor(
        address _core,
        address _pcvDeposit,
        address _psm,
        uint256 _targetBalance,
        address _token,
        uint256 _maxRateLimitPerSecond,
        uint128 _rateLimitPerSecond,
        uint128 _bufferCap
    )
        CoreRef(_core)
        RateLimitedV2(_maxRateLimitPerSecond, _rateLimitPerSecond, _bufferCap)
    {
        pcvDeposit = _pcvDeposit;
        psm = _psm;
        targetBalance = _targetBalance;
        token = _token;
    }

    /// @notice pull ERC20 tokens from pull target and send to push target
    /// if and only if the amount of tokens held in the contract is above
    /// the threshold.
    /// PSM -> PCV Deposit
    function skim() external whenNotPaused {
        /// note this check is redundant, as calculating amountToPull will revert
        /// if pullThreshold is greater than the current balance of psm
        /// however, we like to err on the side of verbosity
        require(
            _checkSkimCondition(),
            "ERC20Allocator: skim condition not met"
        );

        uint256 amountToPull = IERC20(token).balanceOf(psm) - targetBalance;

        _replenishBuffer(amountToPull);

        // pull funds from pull target and send to push target
        PCVDepositV2(psm).withdrawERC20(token, pcvDeposit, amountToPull);

        /// deposit pulled funds into the selected yield venue
        PCVDepositV2(pcvDeposit).deposit();

        emit Skimmed(amountToPull);
    }

    /// @notice push ERC20 tokens to target by pulling from a PCV deposit
    /// and sending to pull target
    /// PCV Deposit -> PSM
    function drip() external whenNotPaused {
        require(
            _checkDripCondition(),
            "ERC20Allocator: drip condition not met"
        );

        /// direct balanceOf call is cheaper than calling balance on psm
        uint256 targetBalanceDelta = targetBalance -
            IERC20(token).balanceOf(psm);
        PCVDepositV2 target = PCVDepositV2(pcvDeposit); /// withdraw from push Target

        /// drip min between target drip amount and pcv deposit being pulled from
        /// to prevent edge cases when a venue runs out of liquidity
        uint256 amountToDrip = Math.min(targetBalanceDelta, target.balance());

        _depleteBuffer(amountToDrip);

        // drip amount to target so that it has dripThreshold amount of tokens
        target.withdraw(psm, amountToDrip);
        emit Dripped(amountToDrip);
    }

    /// @notice function that returns whether the amount of tokens held
    /// are below the target and funds should flow from PCV Deposit -> PSM
    function checkDripCondition() external view override returns (bool) {
        return _checkDripCondition();
    }

    /// @notice function that returns whether the amount of tokens held
    /// are above the target and funds should flow from PSM -> PCV Deposit
    function checkSkimCondition() external view override returns (bool) {
        return _checkSkimCondition();
    }

    function _checkDripCondition() internal view returns (bool) {
        /// direct balanceOf call is cheaper than calling balance on psm
        return IERC20(token).balanceOf(psm) < targetBalance;
    }

    function _checkSkimCondition() internal view returns (bool) {
        /// direct balanceOf call is cheaper than calling balance on psm
        return IERC20(token).balanceOf(psm) > targetBalance;
    }

    /// @notice withdraw tokens from the PCV allocation
    /// @param amountUnderlying of tokens withdrawn
    /// @param to the address to send PCV to
    function withdraw(address to, uint256 amountUnderlying)
        external
        override
        onlyPCVController
    {
        _withdrawERC20(token, to, amountUnderlying);
    }

    /// @notice set the pull threshold
    /// @param newTargetBalance the new amount over which any excess funds will be sent
    /// and under which assets will be replenished
    function setTargetBalance(uint256 newTargetBalance)
        external
        override
        onlyGovernor
    {
        uint256 oldTargetBalance = targetBalance;

        targetBalance = newTargetBalance;

        emit TargetBalanceUpdate(oldTargetBalance, newTargetBalance);
    }

    /// @notice no-op
    function deposit() external override {}

    /// @notice this contract should never hold funds,
    /// it simply routes them between PCV Deposits
    function balance() public view override returns (uint256) {
        if (targetBalance > 0) {} /// shhh
        return 0;
    }

    /// @notice display the related token of the balance reported
    function balanceReportedIn() public view override returns (address) {
        return token;
    }
}
