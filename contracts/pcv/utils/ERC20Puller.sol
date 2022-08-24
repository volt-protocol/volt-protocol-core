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
contract ERC20Puller is CoreRef, PCVDepositV2 {
    using Address for address payable;

    /// @notice event emitted when tokens are dripped
    event Pulled(uint256 amount);

    /// @notice target address to send excess tokens
    address public immutable pushTarget;

    /// @notice target address to pull excess tokens from
    address public immutable pullTarget;

    /// @notice target token address to send
    address public immutable token;

    /// @notice only pull if and only if balance of target is greater than pullThreshold
    uint256 public immutable pullThreshold;

    /// @notice ERC20 PCV Puller constructor
    /// @param _core Volt Core for reference
    /// @param _pushTarget address to push funds
    /// @param _pullTarget address to pull from
    /// @param _pullThreshold amount over which any excess gets sent to the target
    /// @param _token ERC20 to pull
    constructor(
        address _core,
        address _pushTarget,
        address _pullTarget,
        uint256 _pullThreshold,
        address _token
    ) CoreRef(_core) {
        pushTarget = _pushTarget;
        pullTarget = _pullTarget;
        pullThreshold = _pullThreshold;
        token = _token;
    }

    /// @notice pull ERC20 tokens from pull target and send to push target
    /// if and only if the amount of tokens held in the contract is above
    /// the threshold.
    function pull() external whenNotPaused {
        /// note this check is redundant, as calculating amountToPull will revert
        /// if pullThreshold is greater than the current balance of pullTarget
        /// however, we like to err on the side of verbosity
        require(checkCondition(), "ERC20Puller: condition not met");

        uint256 amountToPull = IERC20(token).balanceOf(pullTarget) -
            pullThreshold;

        // pull funds from pull target and send to push target
        PCVDepositV2(pullTarget).withdrawERC20(token, pushTarget, amountToPull);

        /// deposit pulled funds into the selected yield venue
        PCVDepositV2(pushTarget).deposit();

        emit Pulled(amountToPull);
    }

    /// @notice function that returns whether the amount of tokens held
    /// are above the threshold
    function checkCondition() public view returns (bool) {
        return IERC20(token).balanceOf(pullTarget) > pullThreshold;
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

    /// @notice this contract should never hold funds,
    /// it simply routes them between PCV Deposits
    function balance() public view override returns (uint256) {
        if (pullThreshold > 0) {} /// shhh
        return 0;
    }

    /// @notice display the related token of the balance reported
    function balanceReportedIn() public view override returns (address) {
        return token;
    }
}
