// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

/**
 @title Volt DAO ACL Roles
 @notice Holds a complete list of all roles which can be held by contracts inside Volt DAO.
         Roles are broken up into 3 categories:
         * Major Roles - the most powerful roles in Volt, which should be carefully managed.
         * Admin Roles - roles with management capability over critical functionality. Should only be held by automated or optimistic mechanisms
         * Minor Roles - operational roles. May be held or managed by shorter optimistic timelocks or trusted multisigs.
 */
library VoltRoles {
    /*///////////////////////////////////////////////////////////////
                                 Major Roles
    //////////////////////////////////////////////////////////////*/

    /// @notice the ultimate role of Volt. Controls all other roles and protocol functionality.
    bytes32 internal constant GOVERNOR = keccak256("GOVERNOR_ROLE");

    /// @notice the protector role of Volt. Admin of pause, veto, revoke, and minor roles
    bytes32 internal constant GUARDIAN = keccak256("GUARDIAN_ROLE");

    /// @notice the role which can arbitrarily move PCV in any size from any contract
    bytes32 internal constant PCV_CONTROLLER = keccak256("PCV_CONTROLLER_ROLE");

    /// @notice can mint VOLT arbitrarily
    bytes32 internal constant MINTER = keccak256("MINTER_ROLE");

    /// @notice is able to withdraw whitelisted PCV deposits to a safe address
    bytes32 internal constant PCV_GUARD = keccak256("PCV_GUARD_ROLE");

    /// @notice is able to move PCV between deposits
    bytes32 internal constant PCV_MOVER = keccak256("PCV_MOVER_ROLE");

    /// @notice system state role can lock and unlock the global reentrancy
    /// lock. this allows for a system wide reentrancy lock.
    bytes32 internal constant LOCKER = keccak256("LOCKER_ROLE");

    /// ----------- Rate limiters for Global System Entry / Exit ---------------

    /// @notice can replenish and deplete buffer through the GlobalRateLimiter.
    /// replenishing burns Volt, depleting mints Volt
    bytes32 internal constant PSM_MINTER =
        keccak256("PSM_MINTER_ROLE");

    /*///////////////////////////////////////////////////////////////
                                 Minor Roles
    //////////////////////////////////////////////////////////////*/

    /// @notice granted to PCV Deposits
    bytes32 internal constant PCV_DEPOSIT = keccak256("PCV_DEPOSIT_ROLE");
}
