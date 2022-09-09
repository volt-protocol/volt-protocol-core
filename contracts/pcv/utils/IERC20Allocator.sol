pragma solidity =0.8.13;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Timed} from "./../../utils/Timed.sol";
import {CoreRef} from "./../../refs/CoreRef.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Contract to remove all excess funds past a certain threshold from a smart contract
/// used to allocate funds from a PSM to a yield venue so that liquid reserves are minimized
/// This contract should never hold PCV, however it is a PCV Deposit, so if tokens get sent to it,
/// they can still be recovered.
/// @author Volt Protocol
interface IERC20Allocator {
    /// ----------- Events -----------

    /// @notice event emitted when tokens are sent to the pushTarget from the pullTarget
    event Skimmed(uint256 amount);

    /// @notice event emitted when tokens are sent to the pullTarget from the pushTarget
    event Dripped(uint256 amount);

    /// @notice emitted when a new deposit is created
    event DepositCreated(
        address psm,
        address token,
        uint248 targetBalance,
        int8 decimalsNormalizer
    );

    /// @notice emitted when an existing deposit is updated
    event DepositUpdated(
        address psm,
        address token,
        uint248 targetBalance,
        int8 decimalsNormalizer
    );

    /// @notice emitted when a psm is connected to a PCV Deposit
    event DepositConnected(address psm, address pcvDeposit);

    /// @notice emitted when an existing deposit is deleted
    event DepositDeleted(address deposit);

    /// @notice emitted when a PSM is deleted
    event PSMDeleted(address psm);

    /// ----------- Governor Only API -----------

    /// @notice create a new deposit
    /// @param psm Peg Stability Module for this deposit
    /// @param targetBalance target amount of tokens for the PSM to hold
    /// @param decimalsNormalizer decimal normalizer to ensure buffer is depleted and replenished properly
    function createDeposit(
        address psm,
        uint248 targetBalance,
        int8 decimalsNormalizer
    ) external;

    /// @notice edit an existing deposit
    /// @param psm Peg Stability Module for this deposit
    /// @param targetBalance target amount of tokens for the PSM to hold
    /// @param decimalsNormalizer decimal normalizer to ensure buffer is depleted and replenished properly
    function editDeposit(
        address psm,
        uint248 targetBalance,
        int8 decimalsNormalizer
    ) external;

    /// @notice delete an existing deposit
    /// @param psm Peg Stability Module to remove from allocation
    function deletePSM(address psm) external;

    /// @notice establish connection between PSM and a PCV Deposit
    function connectDeposit(address psm, address pcvDeposit) external;

    /// @notice delete connection between PSM and a PCV Deposit
    function deleteDeposit(address pcvDeposit) external;

    /// @notice pull ERC20 tokens from pull target and send to push target
    /// if and only if the amount of tokens held in the contract is above
    /// the threshold.
    function skim(address psm) external;

    /// @notice push ERC20 tokens to PSM by pulling from a PCV deposit
    /// flow of funds: PCV Deposit -> PSM
    function drip(address psm) external;

    /// @notice function that returns whether the amount of tokens held
    /// are above the target and funds should flow from PSM -> PCV Deposit
    function checkSkimCondition(address psm) external view returns (bool);

    /// @notice function that returns whether the amount of tokens held
    /// are below the target and funds should flow from PCV Deposit -> PSM
    function checkDripCondition(address psm) external view returns (bool);

    /// @notice returns whether an action is allowed
    function checkActionAllowed(address psm) external view returns (bool);
}
