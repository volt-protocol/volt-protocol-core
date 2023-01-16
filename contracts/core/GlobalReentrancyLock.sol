// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {VoltRoles} from "./VoltRoles.sol";
import {CoreRefV2} from "./../refs/CoreRefV2.sol";
import {IGlobalReentrancyLock} from "./IGlobalReentrancyLock.sol";

/// @notice inpsired by the openzeppelin reentrancy guard smart contracts
/// data container size has been changed.

/// @dev allows contracts and addresses with the LOCKER role to call
/// in and lock and unlock this smart contract.
/// once locked, only the original caller that locked can unlock the contract
/// without the governor emergency unlock functionality.
/// Governor can unpause if locked but not unlocked.

/// @notice explanation on data types used in contract

/// @dev block number can be safely downcasted without a check on exceeding
/// uint88 max because the sun will explode before this statement is true:
/// block.number > 2^88 - 1
/// address can be stored in a uint160 because an address is only 20 bytes

/// @dev in the EVM. 160bits / 8 bits per byte = 20 bytes
/// https://docs.soliditylang.org/en/develop/types.html#address

contract GlobalReentrancyLock is IGlobalReentrancyLock, CoreRefV2 {
    /// -------------------------------------------------
    /// -------------------------------------------------
    /// ------------------- Constants -------------------
    /// -------------------------------------------------
    /// -------------------------------------------------

    uint8 private constant _NOT_ENTERED = 0;
    uint8 private constant _ENTERED_LEVEL_ONE = 1;
    uint8 private constant _ENTERED_LEVEL_TWO = 2;

    /// ------------- System States ---------------

    /// system unlocked
    /// request level 2 locked
    /// call reverts because system must be locked at level 1 before locking to level 2
    ///
    /// system unlocked
    /// request level 1 locked
    /// level 1 locked, msg.sender stored
    /// level 1 unlocked, msg.sender checked to ensure same as locking
    ///
    /// lock level 1, msg.sender is stored
    /// request level 2 locked
    /// level 2 locked, msg.sender not stored
    /// request level 2 unlocked,
    /// level 2 unlocked, msg.sender not checked
    /// level 1 unlocked, msg.sender checked
    ///
    /// level 1 locked
    /// request level 2 locked
    /// level 2 locked
    /// request level 0 unlocked, invalid state, must unlock to level 1, call reverts
    ///
    /// request level 3 or greater locked from any system state, call reverts

    /// -------------------------------------------------
    /// -------------------------------------------------
    /// --------- Single Storage Slot Per Lock ----------
    /// -------------------------------------------------
    /// -------------------------------------------------

    /// @notice cache the address that locked the system
    /// only this address can unlock it
    address public sender;

    /// @notice store the last block entered
    /// if last block entered was in the past and status
    /// is entered, the system is in an invalid state
    /// which means that actions should be allowed
    uint88 public lastBlockEntered;

    /// @notice system lock level
    uint8 public lockLevel;

    /// @param core reference to core
    constructor(address core) CoreRefV2(core) {}

    /// ---------- View Only APIs ----------

    /// @notice returns the last address that locked this contract
    function lastSender() external view returns (address) {
        return sender;
    }

    /// @notice returns true if the contract is not currently entered
    /// at level 1 and 2, returns false otherwise
    function isUnlocked() external view override returns (bool) {
        return lockLevel == _NOT_ENTERED;
    }

    /// @notice returns whether or not the contract is currently locked
    function isLocked() external view override returns (bool) {
        return lockLevel != _NOT_ENTERED;
    }

    /// ---------- Global Locker Role State Changing APIs ----------

    /// @notice set the status to entered
    /// Callable only by locker role
    /// @dev only valid state transitions:
    /// - lock to level 1 from level 0
    /// - lock to level 2 from level 1
    function lock(
        uint8 toLock
    ) external override onlyVoltRole(VoltRoles.LOCKER) {
        uint8 currentLevel = lockLevel; /// cache to save 1 warm SLOAD

        require(
            toLock == currentLevel + 1,
            "GlobalReentrancyLock: invalid lock level"
        );
        require(
            toLock <= _ENTERED_LEVEL_TWO,
            "GlobalReentrancyLock: exceeds lock state"
        );

        /// only store the sender and lastBlockEntered if first caller (locking to level 1)
        if (currentLevel == _NOT_ENTERED) {
            /// - lock to level 1 from level 0

            uint88 blockEntered = uint88(block.number);

            sender = msg.sender;
            lastBlockEntered = blockEntered;
        } else {
            /// - lock to level 2 from level 1

            /// ------ increasing lock level flow ------

            /// do not update sender, to ensure original sender gets checked on final unlock
            /// do not update lastBlockEntered because it should be the same, if it isn't, revert
            /// if already entered, ensure entry happened this block
            require(
                block.number == lastBlockEntered,
                "GlobalReentrancyLock: system not entered this block"
            );
        }

        lockLevel = toLock;
    }

    /// @notice set the status to not entered
    /// only available if entered in same block
    /// otherwise, system is in an indeterminate state and no execution should be allowed
    /// can only be called by the last address to lock the system
    /// to prevent incorrect system behavior
    /// Only callable by sender's with the locker role
    /// @dev toUnlock can only be _ENTERED_LEVEL_ONE or _NOT_ENTERED
    /// currentLevel cannot be _NOT_ENTERED when this function is called
    /// @dev only valid state transitions:
    /// - unlock to level 0 from level 1 as original locker in same block as lock
    /// - lock from level 2 down to level 1 in same block as lock
    function unlock(
        uint8 toUnlock
    ) external override onlyVoltRole(VoltRoles.LOCKER) {
        uint8 currentLevel = lockLevel;

        require(
            uint88(block.number) == lastBlockEntered,
            "GlobalReentrancyLock: not entered this block"
        );
        require(
            currentLevel != _NOT_ENTERED,
            "GlobalReentrancyLock: system not entered"
        );

        /// if started at level 1, locked up to level 2,
        /// and trying to lock down to level 0,
        /// fail as that puts us in an invalid state

        require(
            toUnlock == currentLevel - 1,
            "GlobalReentrancyLock: unlock level must be 1 lower"
        );

        if (toUnlock == _NOT_ENTERED) {
            /// - unlock to level 0 from level 1, verify sender is original locker
            require(
                msg.sender == sender,
                "GlobalReentrancyLock: caller is not locker"
            );
        }

        lockLevel = toUnlock;
    }

    /// ---------- Governor Only State Changing API ----------

    /// @notice function to recover the system from an incorrect state
    /// in case of emergency by setting status to not entered
    /// only callable if system is entered in a previous block
    function governanceEmergencyRecover() external override onlyGovernor {
        /// must be locked either at level one, or at level 2
        require(
            lockLevel != _NOT_ENTERED,
            "GlobalReentrancyLock: governor recovery, system not entered"
        );
        /// status level 1 or level 2 lock == entered at this point
        /// stop malicious governor from unlocking in the same block as lock happened
        /// if governor is compromised, we're likely in a state FUBAR
        require(
            block.number != lastBlockEntered,
            "GlobalReentrancyLock: cannot unlock in same block as lock"
        );

        lockLevel = _NOT_ENTERED;

        emit EmergencyUnlock(msg.sender, block.timestamp);
    }

    /// @notice governor only function to pause the entire system
    /// sets the lock to level two lock
    /// in this state, pcv oracle updateLiquid and updateIlliquid hooks
    /// are allowed to be called, but since the PCV deposits cannot be called
    /// this presents no issue.
    function governanceEmergencyPause() external override onlyGovernor {
        lockLevel = _ENTERED_LEVEL_TWO;

        emit EmergencyLock(msg.sender, block.timestamp);
    }
}
