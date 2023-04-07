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

    /// @notice can mint CREDIT arbitrarily
    bytes32 internal constant CREDIT_MINTER = keccak256("CREDIT_MINTER_ROLE");

    /// @notice can mint CREDIT within rate limits
    bytes32 internal constant RATE_LIMITED_CREDIT_MINTER =
        keccak256("RATE_LIMITED_CREDIT_MINTER_ROLE");

    /// @notice can mint GUILD arbitrarily
    bytes32 internal constant GUILD_MINTER = keccak256("GUILD_MINTER_ROLE");

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

    /// ----------- GUILD Token Gauge Management ---------------

    /// @notice can manage add new gauges to the system
    bytes32 internal constant GAUGE_ADD = keccak256("GAUGE_ADD_ROLE");

    /// @notice can remove gauges from the system
    bytes32 internal constant GAUGE_REMOVE = keccak256("GAUGE_REMOVE_ROLE");

    /// @notice can manage gauge parameters (max gauges, individual cap)
    bytes32 internal constant GAUGE_PARAMETERS =
        keccak256("GAUGE_PARAMETERS_ROLE");

    /// @notice can notify of losses in a given gauge
    bytes32 internal constant GAUGE_LOSS_NOTIFIER =
        keccak256("GAUGE_LOSS_NOTIFIER_ROLE");

    /// ----------- Timelock management ----------------------------------------
    /// The hashes are the same as OpenZeppelins's roles in TimelockController

    /// @notice can propose new actions in timelocks
    bytes32 internal constant TIMELOCK_PROPOSER = keccak256("PROPOSER_ROLE");
    /// @notice can execute actions in timelocks after their delay
    bytes32 internal constant TIMELOCK_EXECUTOR = keccak256("EXECUTOR_ROLE");
    /// @notice can cancel actions in timelocks
    bytes32 internal constant TIMELOCK_CANCELLER = keccak256("CANCELLER_ROLE");

    /*///////////////////////////////////////////////////////////////
                                Minor Roles
    //////////////////////////////////////////////////////////////*/

    /// @notice granted to PCV Deposits
    bytes32 internal constant PCV_DEPOSIT = keccak256("PCV_DEPOSIT_ROLE");
}
