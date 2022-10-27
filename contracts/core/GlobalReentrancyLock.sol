pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {PermissionsV2} from "./PermissionsV2.sol";
import {IGlobalReentrancyLock} from "./IGlobalReentrancyLock.sol";

/// @notice inpsired by the openzeppelin reentrancy guard smart contracts
/// data container size has been changed
contract GlobalReentrancyLock is IGlobalReentrancyLock, PermissionsV2 {
    using SafeCast for *;

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
    uint224 private constant _NOT_ENTERED = 1;
    uint224 private constant _ENTERED = 2;

    /// entered or not entered
    uint224 private _status;

    /// @notice store the last block entered
    /// if last block entered was in the past and status is entered, the system is in an invalid state
    /// which means that actions should be allowed

    uint32 private _lastBlockEntered;

    /// @notice construct permissions v2
    constructor() PermissionsV2() {
        _status = _NOT_ENTERED;
    }

    /// @notice only system state roles are allowed to call in and set entered
    /// or not entered
    modifier onlyStateRole() {
        require(
            hasRole(SYSTEM_STATE_ROLE, msg.sender),
            "GlobalReentrancyLock: address missing state role"
        );
        _;
    }

    /// @notice returns whether or not the contract is currently not entered
    function isUnlocked() public view returns (bool) {
        return _status == _NOT_ENTERED;
    }

    /// @notice returns whether or not the contract is currently entered
    function isLocked() public view override returns (bool) {
        return _status == _ENTERED;
    }

    /// @notice set the status to entered
    /// only available if not entered
    /// callable only by state role
    function lock() external override onlyStateRole {
        require(
            _status == _NOT_ENTERED,
            "GlobalReentrancyLock: system already entered"
        );

        _status = _ENTERED;
        _lastBlockEntered = block.number.toUint32();
    }

    /// @notice set the status to not entered
    /// only available if entered and entered in same block
    /// otherwise, system is in an indeterminate state and no execution should be allowed
    /// callable only by state role
    function unlock() external override onlyStateRole {
        require(
            block.timestamp == _lastBlockEntered && _status == _ENTERED,
            "GlobalReentrancyLock: system not entered"
        );

        _status = _NOT_ENTERED;
    }

    /// @notice function to recover the system from an incorrect state
    /// in case of emergency by setting status to not entered
    /// only callable if system is entered
    function governanceEmergencyRecover() external override onlyGovernor {
        require(
            _status == _ENTERED,
            "GlobalReentrancyLock: governor recovery, system not entered"
        );

        _status = _NOT_ENTERED;
    }
}
