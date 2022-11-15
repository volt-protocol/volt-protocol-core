pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {PermissionsV2} from "./PermissionsV2.sol";

/// @notice inpsired by the openzeppelin reentrancy guard smart contracts
/// data container size has been changed
interface IGlobalReentrancyLock {
    /// @notice returns true if the contract is currently entered,
    /// returns false otherwise
    function isLocked() external view returns (bool);

    /// @notice returns true if the contract is not currently entered,
    /// returns false otherwise
    function isUnlocked() external view returns (bool);

    /// @notice returns whether or not the contract is currently entered at level 1
    function isLockedLevelOne() external view returns (bool);

    /// @notice returns whether or not the contract is currently entered at level 2
    function isLockedLevelTwo() external view returns (bool);

    /// @notice returns whether or not the contract is currently not entered at level 2
    /// if true, it is possible to lock at level 2
    function isUnlockedLevelTwo() external view returns (bool);

    /// @notice returns whether or not the contract is currently not entered
    /// at level 1 and level 2.
    /// if true, it is possible to lock at level 1
    function isUnlockedLevelOne() external view returns (bool);

    /// @notice set the status to entered
    /// only available if not entered at level 1 and 2
    /// callable only by global locker role
    function lockLevelOne() external;

    /// @notice set the status to entered
    /// only available if entered at level 1 and not level 2
    /// callable only by global locker role
    function lockLevelTwo() external;

    /// @notice set the status to not entered
    /// only available if entered at level 1 and not entered at level 2
    /// callable only by global locker role
    function unlockLevelOne() external;

    /// @notice set the level 2 status to not entered
    /// only available if level 2 entered and level 1 entered
    /// callable only by global locker role
    function unlockLevelTwo() external;

    /// @notice function to recover the system from an incorrect state
    /// in case of emergency by setting status to not entered
    /// only callable if system is entered
    function governanceEmergencyRecover() external;

    /// ------------------------------------------
    /// ----------------- Event ------------------
    /// ------------------------------------------

    /// @notice emitted when governor does an emergency unlock
    event EmergencyUnlock(address indexed sender, uint256 timestamp);
}
