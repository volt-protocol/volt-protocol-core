pragma solidity =0.8.13;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Timed} from "./../../utils/Timed.sol";
import {CoreRef} from "./../../refs/CoreRef.sol";
import {PCVDeposit} from "./../PCVDeposit.sol";
import {RateLimitedV2} from "./../../utils/RateLimitedV2.sol";
import {IERC20Allocator} from "./IERC20Allocator.sol";

/// @notice Contract to remove all excess funds past a target balance from a smart contract
/// and to add funds to that same smart contract when it is under the target balance.
/// First application is allocating funds from a PSM to a yield venue so that liquid reserves are minimized.
/// This contract should never hold PCV, however it has a sweep function, so if tokens get sent to it accidentally,
/// they can still be recovered.
/// @author Elliot Friedman
contract ERC20Allocator is IERC20Allocator, CoreRef, RateLimitedV2 {
    using Address for address payable;
    using SafeERC20 for IERC20;
    using SafeCast for *;

    /// @notice container that stores information on all psm's and their respective deposits
    struct depositInfo {
        /// @notice target address to send excess tokens, will be a Compound PCV Deposit
        address pcvDeposit;
        /// @notice target token address to send
        address token;
        /// @notice only skim if balance of target is greater than targetBalance
        /// only drip if balance of target is less than targetBalance
        uint248 targetBalance;
        /// @notice decimal normalizer to ensure buffer is updated uniformly across all deposits
        int8 decimalsNormalizer;
    }

    /// @notice map the psm address to the corresponding deposit information
    /// excess tokens past target balance will be pulled from the PSM
    /// if PSM has less than the target balance,  will be pulled from the PSM
    mapping(address => depositInfo) public allDeposits;

    /// @notice ERC20 Allocator constructor
    /// @param _core Volt Core for reference
    /// @param _maxRateLimitPerSecond maximum rate limit per second that governance can set
    /// @param _rateLimitPerSecond starting rate limit per second
    /// @param _bufferCap cap on buffer size for this rate limited instance
    constructor(
        address _core,
        uint256 _maxRateLimitPerSecond,
        uint128 _rateLimitPerSecond,
        uint128 _bufferCap
    )
        CoreRef(_core)
        RateLimitedV2(_maxRateLimitPerSecond, _rateLimitPerSecond, _bufferCap)
    {}

    /// ----------- Governor Only API -----------

    /// @notice create a new deposit
    /// @param psm Peg Stability Module for this deposit
    /// @param pcvDeposit that this PSM is linked to
    /// @param targetBalance target amount of tokens for the PSM to hold
    /// @param decimalsNormalizer decimal normalizer to ensure buffer is depleted and replenished properly
    function createDeposit(
        address psm,
        address pcvDeposit,
        uint248 targetBalance,
        int8 decimalsNormalizer
    ) external override onlyGovernor {
        address token = PCVDeposit(pcvDeposit).balanceReportedIn();

        require(
            allDeposits[psm].token == address(0) &&
                allDeposits[psm].pcvDeposit == address(0),
            "ERC20Allocator: cannot overwrite existing deposit"
        );
        require(
            token != address(0),
            "ERC20Allocator: underlying token invalid"
        );

        depositInfo memory newDeposit = depositInfo({
            pcvDeposit: pcvDeposit,
            token: token,
            targetBalance: targetBalance,
            decimalsNormalizer: decimalsNormalizer
        });
        allDeposits[psm] = newDeposit;

        emit DepositCreated(
            psm,
            pcvDeposit,
            token,
            targetBalance,
            decimalsNormalizer
        );
    }

    /// @notice edit an existing deposit
    /// @param psm Peg Stability Module for this deposit
    /// @param pcvDeposit that this PSM is linked to
    /// @param targetBalance target amount of tokens for the PSM to hold
    /// @param decimalsNormalizer decimal normalizer to ensure buffer is depleted and replenished properly
    function editDeposit(
        address psm,
        address pcvDeposit,
        uint248 targetBalance,
        int8 decimalsNormalizer
    ) external override onlyGovernor {
        address token = PCVDeposit(pcvDeposit).balanceReportedIn();

        require(
            allDeposits[psm].token != address(0) &&
                allDeposits[psm].pcvDeposit != address(0),
            "ERC20Allocator: cannot edit non-existent deposit"
        );
        require(
            token != address(0),
            "ERC20Allocator: underlying token invalid"
        );

        depositInfo memory depositToEdit = depositInfo({
            pcvDeposit: pcvDeposit,
            token: token,
            targetBalance: targetBalance,
            decimalsNormalizer: decimalsNormalizer
        });
        allDeposits[psm] = depositToEdit;

        emit DepositUpdated(
            psm,
            pcvDeposit,
            token,
            targetBalance,
            decimalsNormalizer
        );
    }

    /// @notice delete an existing deposit
    /// @param psm Peg Stability Module to remove from allocation
    function deleteDeposit(address psm) external override onlyGovernor {
        delete allDeposits[psm];

        emit DepositDeleted(psm);
    }

    /// @notice sweep target token, this shouldn't ever be needed as this contract
    /// does not hold tokens
    /// @param token to sweep
    /// @param to recipient
    /// @param amount of token to be sent
    function sweep(
        address token,
        address to,
        uint256 amount
    ) external onlyGovernor {
        IERC20(token).safeTransfer(to, amount);
    }

    /// ----------- Permissionless PCV Allocation APIs -----------

    /// @notice pull ERC20 tokens from PSM and send to PCV Deposit
    /// if the amount of tokens held in the PSM is above
    /// the target balance.
    function skim(address psm) external whenNotPaused {
        _skim(psm);
    }

    function _skim(address psm) internal {
        /// Check

        /// note this check is redundant, as calculating amountToPull will revert
        /// if pullThreshold is greater than the current balance of psm
        /// however, we like to err on the side of verbosity
        require(
            _checkSkimCondition(psm),
            "ERC20Allocator: skim condition not met"
        );

        depositInfo memory toSkim = allDeposits[psm];
        address token = toSkim.token;
        address pcvDeposit = toSkim.pcvDeposit;

        uint256 amountToPull = IERC20(token).balanceOf(psm) -
            toSkim.targetBalance;

        /// adjust amount to skim based on the decimals normalizer to replenish buffer
        uint256 adjustedAmountToSkim = getAdjustedAmount(
            amountToPull,
            toSkim.decimalsNormalizer
        );

        /// Effects

        _replenishBuffer(adjustedAmountToSkim);

        /// Interactions

        // pull funds from pull target and send to push target
        PCVDeposit(psm).withdrawERC20(token, pcvDeposit, amountToPull);

        /// deposit pulled funds into the selected yield venue
        PCVDeposit(pcvDeposit).deposit();

        emit Skimmed(amountToPull);
    }

    /// @notice push ERC20 tokens to PSM by pulling from a PCV deposit
    /// flow of funds: PCV Deposit -> PSM
    function drip(address psm) external whenNotPaused {
        _drip(psm);
    }

    /// helper function that does the dripping
    function _drip(address psm) internal {
        /// Check
        require(
            _checkDripCondition(psm),
            "ERC20Allocator: drip condition not met"
        );

        (
            uint256 amountToDrip,
            uint256 adjustedAmountToDrip,
            PCVDeposit target
        ) = getDripDetails(psm);

        /// Effects

        /// deplete buffer with adjusted amount so that it gets
        /// depleted uniformly across all assets and deposits
        _depleteBuffer(adjustedAmountToDrip);

        /// Interaction

        /// drip amount to target so that it has dripThreshold amount of tokens
        target.withdraw(psm, amountToDrip);
        emit Dripped(amountToDrip);
    }

    /// @notice does an action if any are available
    /// @param psm peg stability module to run action on
    function doAction(address psm) external whenNotPaused {
        if (_checkDripCondition(psm)) {
            _drip(psm);
        } else if (_checkSkimCondition(psm)) {
            _skim(psm);
        }
    }

    /// ----------- PURE & VIEW Only APIs -----------

    /// @notice returns the target balance for a given PSM
    function targetBalance(address psm) public view returns (uint256) {
        return allDeposits[psm].targetBalance;
    }

    /// @notice function to get the adjusted amount out
    /// @param amountToDrip the amount to adjust
    /// @param decimalsNormalizer the amount of decimals to adjust amount by
    function getAdjustedAmount(uint256 amountToDrip, int8 decimalsNormalizer)
        public
        pure
        returns (uint256 adjustedAmountToDrip)
    {
        if (decimalsNormalizer == 0) {
            adjustedAmountToDrip = amountToDrip;
        } else if (decimalsNormalizer < 0) {
            uint256 scalingFactor = 10**(-1 * decimalsNormalizer).toUint256();
            adjustedAmountToDrip = amountToDrip / scalingFactor;
        } else {
            uint256 scalingFactor = 10**decimalsNormalizer.toUint256();
            adjustedAmountToDrip = amountToDrip * scalingFactor;
        }
    }

    /// @notice return the amount that can be dripped to a given PSM
    /// @param psm peg stability module to check drip amount on
    /// returns amount that can be dripped, adjusted amount to drip and target
    function getDripDetails(address psm)
        public
        view
        returns (
            uint256 amountToDrip,
            uint256 adjustedAmountToDrip,
            PCVDeposit target
        )
    {
        depositInfo memory toDrip = allDeposits[psm];

        /// direct balanceOf call is cheaper than calling balance on psm
        uint256 targetBalanceDelta = toDrip.targetBalance -
            IERC20(toDrip.token).balanceOf(psm);

        target = PCVDeposit(toDrip.pcvDeposit); /// withdraw from push Target

        /// drip min between target drip amount and pcv deposit being pulled from
        /// to prevent edge cases when a venue runs out of liquidity
        /// only drip the lowest between amount and the buffer,
        /// as dripping more than the buffer will result in
        amountToDrip = Math.min(
            Math.min(targetBalanceDelta, target.balance()),
            buffer()
        );

        /// adjust amount to drip based on the decimals normalizer to deplete buffer
        adjustedAmountToDrip = getAdjustedAmount(
            amountToDrip,
            toDrip.decimalsNormalizer
        );
    }

    /// @notice function that returns whether the amount of tokens held
    /// are below the target and funds should flow from PCV Deposit -> PSM
    /// returns false when paused
    /// @param psm peg stability module to check drip condition
    function checkDripCondition(address psm)
        external
        view
        override
        returns (bool)
    {
        return _checkDripCondition(psm) && paused() == false && buffer() > 0;
    }

    /// @notice function that returns whether the amount of tokens held
    /// are above the target and funds should flow from PSM -> PCV Deposit
    /// returns false when paused
    function checkSkimCondition(address psm)
        external
        view
        override
        returns (bool)
    {
        return _checkSkimCondition(psm) && paused() == false;
    }

    /// @notice returns whether an action is allowed
    /// returns false when paused
    function checkActionAllowed(address psm)
        external
        view
        override
        returns (bool)
    {
        return
            (_checkDripCondition(psm) || _checkSkimCondition(psm)) &&
            paused() == false;
    }

    function _checkDripCondition(address psm) internal view returns (bool) {
        /// direct balanceOf call is cheaper than calling balance on psm
        return
            IERC20(allDeposits[psm].token).balanceOf(psm) <
            allDeposits[psm].targetBalance;
    }

    function _checkSkimCondition(address psm) internal view returns (bool) {
        /// direct balanceOf call is cheaper than calling balance on psm
        return
            IERC20(allDeposits[psm].token).balanceOf(psm) >
            allDeposits[psm].targetBalance;
    }
}
