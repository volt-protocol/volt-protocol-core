pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {PermissionsV2} from "./PermissionsV2.sol";

/// @notice inpsired by the openzeppelin reentrancy guard smart contracts
/// data container size has been changed
interface IGlobalReentrancyLock {
    /// @notice returns whether or not the contract is currently entered
    function isLocked() external view returns (bool);

    /// @notice set the status to entered
    /// only available if not entered
    /// callable only by global  role
    function lock() external;

    /// @notice set the status to not entered
    /// only available if entered
    /// callable only by global locker role
    function unlock() external;

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
