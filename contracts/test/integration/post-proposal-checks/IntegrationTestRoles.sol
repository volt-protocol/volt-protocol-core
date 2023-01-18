// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {PostProposalCheck} from "./PostProposalCheck.sol";

import {CoreV2} from "../../../core/CoreV2.sol";
import {VoltRoles} from "../../../core/VoltRoles.sol";

contract IntegrationTestRoles is PostProposalCheck {
    function testMainnetRoles() public {
        CoreV2 core = CoreV2(addresses.mainnet("CORE"));

        // GOVERNOR
        assertEq(core.getRoleAdmin(VoltRoles.GOVERNOR), VoltRoles.GOVERNOR);
        assertEq(core.getRoleMemberCount(VoltRoles.GOVERNOR), 3);
        assertEq(
            core.getRoleMember(VoltRoles.GOVERNOR, 0),
            addresses.mainnet("CORE")
        );
        assertEq(
            core.getRoleMember(VoltRoles.GOVERNOR, 1),
            addresses.mainnet("GOVERNOR")
        );
        assertEq(
            core.getRoleMember(VoltRoles.GOVERNOR, 2),
            addresses.mainnet("TIMELOCK_CONTROLLER")
        );

        // PCV_CONTROLLER
        assertEq(
            core.getRoleAdmin(VoltRoles.PCV_CONTROLLER),
            VoltRoles.GOVERNOR
        );
        assertEq(core.getRoleMemberCount(VoltRoles.PCV_CONTROLLER), 6);
        assertEq(
            core.getRoleMember(VoltRoles.PCV_CONTROLLER, 0),
            addresses.mainnet("PSM_ALLOCATOR")
        );
        assertEq(
            core.getRoleMember(VoltRoles.PCV_CONTROLLER, 1),
            addresses.mainnet("PCV_GUARDIAN")
        );
        assertEq(
            core.getRoleMember(VoltRoles.PCV_CONTROLLER, 2),
            addresses.mainnet("PCV_ROUTER")
        );
        assertEq(
            core.getRoleMember(VoltRoles.PCV_CONTROLLER, 3),
            addresses.mainnet("GOVERNOR")
        );
        assertEq(
            core.getRoleMember(VoltRoles.PCV_CONTROLLER, 4),
            addresses.mainnet("PSM_NONCUSTODIAL_DAI")
        );
        assertEq(
            core.getRoleMember(VoltRoles.PCV_CONTROLLER, 5),
            addresses.mainnet("PSM_NONCUSTODIAL_USDC")
        );

        // PCV_MOVER
        assertEq(core.getRoleAdmin(VoltRoles.PCV_MOVER), VoltRoles.GOVERNOR);
        assertEq(core.getRoleMemberCount(VoltRoles.PCV_MOVER), 1);
        assertEq(
            core.getRoleMember(VoltRoles.PCV_MOVER, 0),
            addresses.mainnet("GOVERNOR")
        );

        // LIQUID_PCV_DEPOSIT_ROLE
        assertEq(
            core.getRoleAdmin(VoltRoles.LIQUID_PCV_DEPOSIT),
            VoltRoles.GOVERNOR
        );
        assertEq(core.getRoleMemberCount(VoltRoles.LIQUID_PCV_DEPOSIT), 4);
        assertEq(
            core.getRoleMember(VoltRoles.LIQUID_PCV_DEPOSIT, 0),
            addresses.mainnet("PSM_DAI")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LIQUID_PCV_DEPOSIT, 1),
            addresses.mainnet("PSM_USDC")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LIQUID_PCV_DEPOSIT, 2),
            addresses.mainnet("PCV_DEPOSIT_MORPHO_DAI")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LIQUID_PCV_DEPOSIT, 3),
            addresses.mainnet("PCV_DEPOSIT_MORPHO_USDC")
        );

        // ILLIQUID_PCV_DEPOSIT_ROLE
        assertEq(
            core.getRoleAdmin(VoltRoles.ILLIQUID_PCV_DEPOSIT),
            VoltRoles.GOVERNOR
        );
        assertEq(core.getRoleMemberCount(VoltRoles.ILLIQUID_PCV_DEPOSIT), 0);

        // PCV_GUARD
        assertEq(core.getRoleAdmin(VoltRoles.PCV_GUARD), VoltRoles.GOVERNOR);
        assertEq(core.getRoleMemberCount(VoltRoles.PCV_GUARD), 3);
        assertEq(
            core.getRoleMember(VoltRoles.PCV_GUARD, 0),
            addresses.mainnet("EOA_1")
        );
        assertEq(
            core.getRoleMember(VoltRoles.PCV_GUARD, 1),
            addresses.mainnet("EOA_2")
        );
        assertEq(
            core.getRoleMember(VoltRoles.PCV_GUARD, 2),
            addresses.mainnet("EOA_4")
        );

        // GUARDIAN
        assertEq(core.getRoleAdmin(VoltRoles.GUARDIAN), VoltRoles.GOVERNOR);
        assertEq(core.getRoleMemberCount(VoltRoles.GUARDIAN), 2);
        assertEq(
            core.getRoleMember(VoltRoles.GUARDIAN, 0),
            addresses.mainnet("PCV_GUARDIAN")
        );
        assertEq(
            core.getRoleMember(VoltRoles.GUARDIAN, 1),
            addresses.mainnet("GOVERNOR") // team multisig
        );

        // RATE_LIMIT_SYSTEM_ENTRY_DEPLETE_ROLE
        assertEq(
            core.getRoleAdmin(VoltRoles.RATE_LIMIT_SYSTEM_ENTRY_DEPLETE),
            VoltRoles.GOVERNOR
        );
        assertEq(
            core.getRoleMemberCount(VoltRoles.RATE_LIMIT_SYSTEM_ENTRY_DEPLETE),
            2
        );
        assertEq(
            core.getRoleMember(VoltRoles.RATE_LIMIT_SYSTEM_ENTRY_DEPLETE, 0),
            addresses.mainnet("PSM_DAI")
        );
        assertEq(
            core.getRoleMember(VoltRoles.RATE_LIMIT_SYSTEM_ENTRY_DEPLETE, 1),
            addresses.mainnet("PSM_USDC")
        );

        // RATE_LIMIT_SYSTEM_ENTRY_REPLENISH_ROLE
        assertEq(
            core.getRoleAdmin(VoltRoles.RATE_LIMIT_SYSTEM_ENTRY_REPLENISH),
            VoltRoles.GOVERNOR
        );
        assertEq(
            core.getRoleMemberCount(
                VoltRoles.RATE_LIMIT_SYSTEM_ENTRY_REPLENISH
            ),
            4
        );
        assertEq(
            core.getRoleMember(VoltRoles.RATE_LIMIT_SYSTEM_ENTRY_REPLENISH, 0),
            addresses.mainnet("PSM_DAI")
        );
        assertEq(
            core.getRoleMember(VoltRoles.RATE_LIMIT_SYSTEM_ENTRY_REPLENISH, 1),
            addresses.mainnet("PSM_USDC")
        );
        assertEq(
            core.getRoleMember(VoltRoles.RATE_LIMIT_SYSTEM_ENTRY_REPLENISH, 2),
            addresses.mainnet("PSM_NONCUSTODIAL_DAI")
        );
        assertEq(
            core.getRoleMember(VoltRoles.RATE_LIMIT_SYSTEM_ENTRY_REPLENISH, 3),
            addresses.mainnet("PSM_NONCUSTODIAL_USDC")
        );

        // LOCKER_ROLE
        assertEq(core.getRoleAdmin(VoltRoles.LOCKER), VoltRoles.GOVERNOR);
        assertEq(core.getRoleMemberCount(VoltRoles.LOCKER), 13);
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 0),
            addresses.mainnet("SYSTEM_ENTRY")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 1),
            addresses.mainnet("PSM_ALLOCATOR")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 2),
            addresses.mainnet("PCV_ORACLE")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 3),
            addresses.mainnet("PSM_DAI")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 4),
            addresses.mainnet("PSM_USDC")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 5),
            addresses.mainnet("PCV_DEPOSIT_MORPHO_DAI")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 6),
            addresses.mainnet("PCV_DEPOSIT_MORPHO_USDC")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 7),
            addresses.mainnet("GLOBAL_RATE_LIMITED_MINTER")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 8),
            addresses.mainnet("GLOBAL_SYSTEM_EXIT_RATE_LIMITER")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 9),
            addresses.mainnet("PCV_ROUTER")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 10),
            addresses.mainnet("PCV_GUARDIAN")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 11),
            addresses.mainnet("PSM_NONCUSTODIAL_DAI")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 12),
            addresses.mainnet("PSM_NONCUSTODIAL_USDC")
        );

        // MINTER
        assertEq(core.getRoleAdmin(VoltRoles.MINTER), VoltRoles.GOVERNOR);
        assertEq(core.getRoleMemberCount(VoltRoles.MINTER), 1);
        assertEq(
            core.getRoleMember(VoltRoles.MINTER, 0),
            addresses.mainnet("GLOBAL_RATE_LIMITED_MINTER")
        );

        /// SYSTEM EXIT RATE LIMIT DEPLETER
        assertEq(
            core.getRoleAdmin(VoltRoles.RATE_LIMIT_SYSTEM_EXIT_DEPLETE),
            VoltRoles.GOVERNOR
        );
        assertEq(
            core.getRoleMemberCount(VoltRoles.RATE_LIMIT_SYSTEM_EXIT_DEPLETE),
            3
        );
        assertEq(
            core.getRoleMember(VoltRoles.RATE_LIMIT_SYSTEM_EXIT_DEPLETE, 0),
            addresses.mainnet("PSM_ALLOCATOR")
        );
        assertEq(
            core.getRoleMember(VoltRoles.RATE_LIMIT_SYSTEM_EXIT_DEPLETE, 1),
            addresses.mainnet("PSM_NONCUSTODIAL_DAI")
        );
        assertEq(
            core.getRoleMember(VoltRoles.RATE_LIMIT_SYSTEM_EXIT_DEPLETE, 2),
            addresses.mainnet("PSM_NONCUSTODIAL_USDC")
        );

        /// SYSTEM EXIT RATE LIMIT REPLENISH
        assertEq(
            core.getRoleAdmin(VoltRoles.RATE_LIMIT_SYSTEM_EXIT_REPLENISH),
            VoltRoles.GOVERNOR
        );
        assertEq(
            core.getRoleMemberCount(VoltRoles.RATE_LIMIT_SYSTEM_EXIT_REPLENISH),
            1
        );
        assertEq(
            core.getRoleMember(VoltRoles.RATE_LIMIT_SYSTEM_EXIT_REPLENISH, 0),
            addresses.mainnet("PSM_ALLOCATOR")
        );
    }
}
