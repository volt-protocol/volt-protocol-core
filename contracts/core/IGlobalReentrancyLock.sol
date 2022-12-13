pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {PermissionsV2} from "./PermissionsV2.sol";

/// @notice inpsired by the openzeppelin reentrancy guard smart contracts
/// data container size has been changed
interface IGlobalReentrancyLock {
    /// @notice returns the last address that locked this contract
    function lastSender() external view returns (address);

    /// @notice returns true if the contract is currently entered,
    /// returns false otherwise
    function isLocked() external view returns (bool);

    /// @notice returns true if the contract is not currently entered,
    /// returns false otherwise
    function isUnlocked() external view returns (bool);

    /// @notice returns whether or not the contract is currently entered
    /// if true, and locked in the same block, it is possible to unlock
    function lockLevel() external view returns (uint8);

    /// @notice governor only function to pause the entire system
    /// sets the lock to level two lock
    /// in this state, pcv oracle updateLiquid and updateIlliquid hooks
    /// are allowed to be called, but since the PCV deposits cannot be called
    /// this presents no issue.
    function governanceEmergencyPause() external;

    /// @notice function to recover the system from an incorrect state
    /// in case of emergency by setting status to not entered
    /// only callable if system is entered
    function governanceEmergencyRecover() external;

    /// @notice set the status to entered
    /// only available if not entered at level 1 and level 2
    /// Only callable by locker role
    function lock(uint8 toLock) external;

    /// @notice set the status to not entered
    /// only available if entered and entered in same block
    /// otherwise, system is in an indeterminate state and no execution should be allowed
    /// can only be called by the last address to lock the system
    /// to prevent incorrect system behavior
    /// Only callable by locker level 1 role
    /// @dev toUnlock can only be _ENTERED_LEVEL_ONE or _NOT_ENTERED
    /// currentLevel cannot be _NOT_ENTERED when this function is called
    function unlock(uint8 toUnlock) external;

    /// ------------------------------------------
    /// ----------------- Event ------------------
    /// ------------------------------------------

    /// @notice emitted when governor does an emergency unlock
    event EmergencyUnlock(address indexed sender, uint256 timestamp);

    /// @notice emitted when governor does an emergency lock
    event EmergencyLock(address indexed sender, uint256 timestamp);
}
