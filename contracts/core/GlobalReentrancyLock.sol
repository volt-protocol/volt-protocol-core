pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {PermissionsV2} from "./PermissionsV2.sol";
import {IGlobalReentrancyLock} from "./IGlobalReentrancyLock.sol";

/// @notice inpsired by the openzeppelin reentrancy guard smart contracts
/// data container size has been changed
/// @dev allows contracts with the GLOBAL_LOCKER_ROLE to call in and lock and unlock
/// this smart contract.
/// once locked, only the original caller that locked can unlock the contract
/// without the governor emergency unlock functionality.
/// Governor can unpause if locked but not unlocked.
abstract contract GlobalReentrancyLock is IGlobalReentrancyLock, PermissionsV2 {
    using SafeCast for *;

    /// -------------------------------------------------
    /// -------------------------------------------------
    /// ------------------- Constants -------------------
    /// -------------------------------------------------
    /// -------------------------------------------------

    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint8 private constant _NOT_ENTERED = 1;
    uint8 private constant _ENTERED = 2;

    /// -------------------------------------------------
    /// -------------------------------------------------
    /// -------------- Single Storage Slot --------------
    /// -------------------------------------------------
    /// -------------------------------------------------

    /// @notice cache the address that locked the system
    /// only this address can unlock it
    uint160 private _sender;

    /// @notice store the last block entered
    /// if last block entered was in the past and status is entered, the system is in an invalid state
    /// which means that actions should be allowed
    uint88 private _lastBlockEntered;

    /// @notice whether or not the system is entered or not entered
    uint8 private _status;

    /// @notice construct GlobalReentrancyLock
    constructor() {
        _status = _NOT_ENTERED;
    }

    /// @notice only global locker role is allowed to call in and set entered
    /// or not entered
    modifier onlyGlobalLockerRole() {
        require(
            hasRole(GLOBAL_LOCKER_ROLE, msg.sender),
            "GlobalReentrancyLock: address missing global locker role"
        );
        _;
    }

    /// @notice view only function to return the last block entered
    function lastBlockEntered() external view returns (uint88) {
        return _lastBlockEntered;
    }

    /// @notice returns the last address that locked this contract
    function lastSender() external view returns (address) {
        return address(_sender);
    }

    /// @notice returns whether or not the contract is currently not entered
    /// if true, it is possible to lock
    function isUnlocked() external view returns (bool) {
        return _status == _NOT_ENTERED;
    }

    /// @notice returns whether or not the contract is currently entered
    /// if true, and locked in the same block, it is possible to unlock
    function isLocked() external view override returns (bool) {
        return _status == _ENTERED;
    }

    /// @notice set the status to entered
    /// only available if not entered
    /// callable only by global locker role
    function lock() external override onlyGlobalLockerRole {
        require(
            _status == _NOT_ENTERED,
            "GlobalReentrancyLock: system already entered"
        );

        /// cache values to save a warm SSTORE
        /// block number can be safely downcasted without a check on exceeding
        /// uint88 max because the sun will explode before this statement is true:
        /// block.number > 2^88 - 1
        uint88 blockEntered = uint88(block.number);
        uint160 sender = uint160(msg.sender);

        _sender = sender;
        _lastBlockEntered = blockEntered;
        _status = _ENTERED;
    }

    /// @notice set the status to not entered
    /// only available if entered and entered in same block
    /// otherwise, system is in an indeterminate state and no execution should be allowed
    /// callable only by global locker role
    /// can only be called by the last address to lock the system
    /// to prevent incorrect system behavior
    function unlock() external override onlyGlobalLockerRole {
        require(
            uint160(msg.sender) == _sender,
            "GlobalReentrancyLock: caller is not locker"
        );
        require(
            uint88(block.number) == _lastBlockEntered && _status == _ENTERED,
            "GlobalReentrancyLock: system not entered"
        );

        _status = _NOT_ENTERED;
    }

    /// @notice function to recover the system from an incorrect state
    /// in case of emergency by setting status to not entered
    /// only callable if system is entered in a previous block
    function governanceEmergencyRecover() external override onlyGovernor {
        require(
            _status == _ENTERED,
            "GlobalReentrancyLock: governor recovery, system not entered"
        );
        /// we know status == entered at this point
        require(
            block.number > _lastBlockEntered,
            "GlobalReentrancyLock: cannot unlock in same block as lock"
        );

        _status = _NOT_ENTERED;

        emit EmergencyUnlock(msg.sender, block.timestamp);
    }
}
