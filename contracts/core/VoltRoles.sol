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
    bytes32 internal constant GOVERNOR = keccak256("GOVERN_ROLE");

    /// @notice the protector role of Volt. Admin of pause, veto, revoke, and minor roles
    bytes32 internal constant GUARDIAN = keccak256("GUARDIAN_ROLE");

    /// @notice the role which can arbitrarily move PCV in any size from any contract
    bytes32 internal constant PCV_CONTROLLER = keccak256("PCV_CONTROLLER_ROLE");

    /// @notice can mint VOLT arbitrarily
    bytes32 internal constant MINTER = keccak256("MINTER_ROLE");

    /// @notice can mint VOLT through GlobalRateLimitedMinter on a rate limit
    bytes32 internal constant VOLT_MINTER_ROLE = keccak256("VOLT_MINTER_ROLE");

    /// @notice is able to withdraw whitelisted PCV deposits to a safe address
    bytes32 internal constant PCV_GUARD = keccak256("PCV_GUARD_ROLE");

    /// @notice system state role can lock and unlock the global reentrancy
    /// lock. this allows for a system wide reentrancy lock.
    bytes32 internal constant GLOBAL_LOCKER_ROLE =
        keccak256("GLOBAL_LOCKER_ROLE");

    /*///////////////////////////////////////////////////////////////
                                 Admin Roles
    //////////////////////////////////////////////////////////////*/

    /// @notice manages the granting and revocation of PCV Guard roles
    bytes32 internal constant PCV_GUARD_ADMIN =
        keccak256("PCV_GUARD_ADMIN_ROLE");

    /*///////////////////////////////////////////////////////////////
                                 Minor Roles
    //////////////////////////////////////////////////////////////*/

    /// @notice capable of changing PCV Deposit and Global Rate Limited Minter in the PSM
    bytes32 internal constant PSM_ADMIN_ROLE = keccak256("PSM_ADMIN_ROLE");
}