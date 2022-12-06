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
    bytes32 internal constant GOVERN = keccak256("GOVERN_ROLE");

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

    /// @notice can mint VOLT through GlobalRateLimitedMinter on a rate limit
    bytes32 internal constant RATE_LIMIT_SYSTEM_ENTRY_DEPLETE =
        keccak256("RATE_LIMIT_SYSTEM_ENTRY_DEPLETE_ROLE");

    /// @notice can redeem VOLT and replenish the GlobalRateLimitedMinter buffer
    /// @notice non custodial PSM role.
    bytes32 internal constant RATE_LIMIT_SYSTEM_ENTRY_REPLENISH =
        keccak256("RATE_LIMIT_SYSTEM_ENTRY_REPLENISH_ROLE");

    /// @notice can delpete buffer through the GlobalSystemExitRateLimiter buffer
    bytes32 internal constant RATE_LIMIT_SYSTEM_EXIT_DEPLETE =
        keccak256("RATE_LIMIT_SYSTEM_EXIT_DEPLETE_ROLE");

    /// @notice can replenish buffer through GlobalSystemExitRateLimiter
    bytes32 internal constant RATE_LIMIT_SYSTEM_EXIT_REPLENISH =
        keccak256("RATE_LIMIT_SYSTEM_EXIT_REPLENISH_ROLE");

    /*///////////////////////////////////////////////////////////////
                                 Minor Roles
    //////////////////////////////////////////////////////////////*/

    /// @notice granted to liquid PCV Deposits
    bytes32 internal constant LIQUID_PCV_DEPOSIT =
        keccak256("LIQUID_PCV_DEPOSIT_ROLE");
    /// @notice granted to illiquid PCV Deposits
    bytes32 internal constant ILLIQUID_PCV_DEPOSIT =
        keccak256("ILLIQUID_PCV_DEPOSIT_ROLE");
}
