pragma solidity 0.8.13;

import {PermissionsV2} from "./PermissionsV2.sol";
import {IGlobalReentrancyLock} from "./IGlobalReentrancyLock.sol";

/// @notice inpsired by the openzeppelin reentrancy guard smart contracts
/// data container size has been changed.
/// @dev allows contracts and addresses with the LEVEL_ONE_LOCKER_ROLE to call
/// in and lock and unlock this smart contract.
/// once locked, only the original caller that locked can unlock the contract
/// without the governor emergency unlock functionality.
/// Governor can unpause if locked but not unlocked.
abstract contract GlobalReentrancyLock is IGlobalReentrancyLock, PermissionsV2 {
    /// -------------------------------------------------
    /// -------------------------------------------------
    /// ------------------- Constants -------------------
    /// -------------------------------------------------
    /// -------------------------------------------------

    uint8 private constant _NOT_ENTERED = 0;
    uint8 private constant _ENTERED = 1;

    /// -------------------------------------------------
    /// -------------------------------------------------
    /// --------- Single Storage Slot Per Lock ----------
    /// -------------------------------------------------
    /// -------------------------------------------------

    /// ------------- System States ---------------

    /// level 1 unlocked
    /// request level 2 locked
    /// level 2 locked, msg.sender stored
    /// level 2 unlocked, msg.sender checked
    ///
    /// level 1 unlocked
    /// request level 1 locked
    /// level 1 locked, msg.sender stored
    /// level 1 unlocked, msg.sender checked
    ///
    /// level 1 locked
    /// request level 2 locked
    /// level 2 locked, msg.sender not stored
    /// level 2 unlocked, msg.sender not checked
    /// level 1 unlocked, msg.sender checked

    /// @notice cache the address that locked the system
    /// only this address can unlock it
    uint160 private _sender;

    /// @notice store the last block entered
    /// if last block entered was in the past and status
    /// is entered, the system is in an invalid state
    /// which means that actions should be allowed
    uint80 private _lastBlockEntered;

    /// @notice whether or not the system is entered or not entered at level 1
    uint8 private _statusLevelOne;

    /// @notice whether or not the system is entered or not entered at level 2
    uint8 private _statusLevelTwo;

    /// @notice only level 1 locker role is allowed to call
    /// in and set entered or not entered for status level one
    modifier onlyLockerLevelOneRole() {
        require(
            hasRole(LEVEL_ONE_LOCKER_ROLE, msg.sender),
            "GlobalReentrancyLock: address missing global locker level one role"
        );
        _;
    }
    /// @notice only level 1 locker role is allowed to call
    /// in and set entered or not entered for status level one
    modifier onlyLockerLevelTwoRole() {
        require(
            hasRole(LEVEL_TWO_LOCKER_ROLE, msg.sender),
            "GlobalReentrancyLock: address missing global locker level two role"
        );
        _;
    }

    /// ---------- View Only APIs ----------

    /// @notice view only function to return the last block entered
    function lastBlockEntered() external view returns (uint80) {
        return _lastBlockEntered;
    }

    /// @notice returns the last address that locked this contract
    function lastSender() external view returns (address) {
        return address(_sender);
    }

    /// @notice returns true if the contract is not currently entered
    /// at level 1 and 2, returns false otherwise
    function isUnlocked() external view override returns (bool) {
        return
            _statusLevelOne == _NOT_ENTERED && _statusLevelTwo == _NOT_ENTERED;
    }

    /// @notice returns whether or not the contract is currently entered
    /// if true, and locked in the same block, it is possible to unlock
    function isLocked() external view override returns (bool) {
        return _statusLevelOne == _ENTERED || _statusLevelTwo == _ENTERED;
    }

    /// @notice returns whether or not the contract is currently not entered
    /// if level one or level two is locked, return false
    /// if true, it is possible to lock both levels 1 and 2
    function isUnlockedLevelOne() external view override returns (bool) {
        return
            _statusLevelOne == _NOT_ENTERED && _statusLevelTwo == _NOT_ENTERED;
    }

    /// @notice returns whether or not the contract is currently not entered at level 2
    /// if true, it is possible to lock at level 2
    function isUnlockedLevelTwo() external view override returns (bool) {
        return _statusLevelTwo == _NOT_ENTERED;
    }

    /// @notice returns whether or not the contract is currently entered
    /// if true, and locked in the same block, it is possible to unlock
    function isLockedLevelOne() external view override returns (bool) {
        return _statusLevelOne == _ENTERED || _statusLevelTwo == _ENTERED;
    }

    /// @notice returns whether or not the contract is currently entered
    /// if true, and locked in the same block, it is possible to unlock
    function isLockedLevelTwo() external view override returns (bool) {
        return _statusLevelTwo == _ENTERED;
    }

    /// ---------- Global Locker Role State Changing APIs ----------

    /// @notice set the status to entered
    /// only available if not entered
    /// callable only by global locker role
    /// Only callable by locker level 1 role
    function lockLevelOne() external override onlyLockerLevelOneRole {
        require(
            _statusLevelOne == _NOT_ENTERED,
            "GlobalReentrancyLock: system locked level 1"
        );
        require(
            _statusLevelTwo == _NOT_ENTERED,
            "GlobalReentrancyLock: system locked level 2"
        );

        /// cache values to save a warm SSTORE
        /// block number can be safely downcasted without a check on exceeding
        /// uint80 max because the sun will explode before this statement is true:
        /// block.number > 2^80 - 1
        uint80 blockEntered = uint80(block.number);

        /// address can be stored in a uint160 because an address is only 20 bytes
        /// in the EVM. 160bits / 8 bits per byte = 20 bytes
        /// https://docs.soliditylang.org/en/develop/types.html#address
        uint160 sender = uint160(msg.sender);

        _sender = sender;
        _lastBlockEntered = blockEntered;
        _statusLevelOne = _ENTERED;
    }

    /// @notice set the status to entered
    /// only available if not entered
    /// callable only by global locker role
    /// Only callable by locker level 2 role
    function lockLevelTwo() external override onlyLockerLevelTwoRole {
        require(
            _statusLevelTwo == _NOT_ENTERED,
            "GlobalReentrancyLock: system already locked level 2"
        );

        /// if already entered at level 1, don't store address to validate
        /// for unlocking of level 2
        if (_statusLevelOne == _ENTERED) {
            /// if already entered, ensure entered in this block
            require(
                block.number == _lastBlockEntered,
                "GlobalReentrancyLock: system not entered this block level 2"
            );

            /// don't write lastBlock entered because it has not changed
            _statusLevelTwo = _ENTERED;
        } else {
            /// cache values to save a warm SSTORE
            /// block number can be safely downcasted without a check on exceeding
            /// uint80 max because the sun will explode before this statement is true:
            /// block.number > 2^80 - 1
            uint80 blockEntered = uint80(block.number);

            /// address can be stored in a uint160 because an address is only 20 bytes
            /// in the EVM. 160bits / 8 bits per byte = 20 bytes
            /// https://docs.soliditylang.org/en/develop/types.html#address
            uint160 sender = uint160(msg.sender);

            _sender = sender;
            _lastBlockEntered = blockEntered;
            _statusLevelTwo = _ENTERED;
        }
    }

    /// @notice set the status to not entered
    /// only available if entered and entered in same block
    /// otherwise, system is in an indeterminate state and no execution should be allowed
    /// callable only by global locker role
    /// can only be called by the last address to lock the system
    /// to prevent incorrect system behavior
    /// Only callable by locker level 1 role
    function unlockLevelOne() external override onlyLockerLevelOneRole {
        /// address can be stored in a uint160 because an address is only 20 bytes
        /// in the EVM. 160bits / 8 bits per byte = 20 bytes
        /// https://docs.soliditylang.org/en/develop/types.html#address
        require(
            uint160(msg.sender) == _sender,
            "GlobalReentrancyLock: caller is not locker"
        );

        /// block number can be safely downcasted without a check on exceeding
        /// uint80 max because the sun will explode before this statement is true:
        /// block.number > 2^80 - 1
        require(
            uint80(block.number) == _lastBlockEntered,
            "GlobalReentrancyLock: not entered this block"
        );
        require(
            _statusLevelOne == _ENTERED,
            "GlobalReentrancyLock: system not entered"
        );
        /// cannot unlock level one if level 2 is still locked
        require(
            _statusLevelTwo == _NOT_ENTERED,
            "GlobalReentrancyLock: system entered level 2"
        );

        _statusLevelOne = _NOT_ENTERED;
    }

    /// @notice set the status to not entered
    /// only available if entered and entered in same block
    /// otherwise, system is in an indeterminate state and no execution should be allowed
    /// callable only by global locker role
    /// can only be called by the last address to lock the system
    /// to prevent incorrect system behavior
    /// Only callable by locker level 2 role
    function unlockLevelTwo() external override onlyLockerLevelTwoRole {
        /// block number can be safely downcasted without a check on exceeding
        /// uint80 max because the sun will explode before this statement is true:
        /// block.number > 2^80 - 1
        require(
            uint80(block.number) == _lastBlockEntered,
            "GlobalReentrancyLock: not entered this block"
        );
        require(
            _statusLevelTwo == _ENTERED,
            "GlobalReentrancyLock: system not entered level 2"
        );

        /// if status level one isn't entered, msg.sender stored as locking address
        /// should be the same as the unlocking address
        if (_statusLevelOne == _NOT_ENTERED) {
            /// address can be stored in a uint160 because an address is only 20 bytes
            /// in the EVM. 160bits / 8 bits per byte = 20 bytes
            /// https://docs.soliditylang.org/en/develop/types.html#address
            require(
                uint160(msg.sender) == _sender,
                "GlobalReentrancyLock: caller is not level 2 locker"
            );
        }

        _statusLevelTwo = _NOT_ENTERED;
    }

    /// ---------- Governor Only State Changing API ----------

    /// @notice function to recover the system from an incorrect state
    /// in case of emergency by setting status to not entered
    /// only callable if system is entered in a previous block
    function governanceEmergencyRecover() external override onlyGovernor {
        /// must be locked either at level one, or at level 2
        require(
            _statusLevelOne == _ENTERED || _statusLevelTwo == _ENTERED,
            "GlobalReentrancyLock: governor recovery, system not entered"
        );
        /// status level 1 or level 2 lock == entered at this point
        /// stop malicious governor from unlocking in the same block as lock happened
        /// if governor is compromised, we're likely in a state FUBAR
        require(
            block.number != _lastBlockEntered,
            "GlobalReentrancyLock: cannot unlock in same block as lock"
        );

        /// set lock status at both levels to unlocked
        _statusLevelOne = _NOT_ENTERED;
        _statusLevelTwo = _NOT_ENTERED;

        emit EmergencyUnlock(msg.sender, block.timestamp);
    }
}
