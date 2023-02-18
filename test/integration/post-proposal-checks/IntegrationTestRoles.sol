// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {PostProposalCheck} from "@test/integration/post-proposal-checks/PostProposalCheck.sol";

import {CoreV2} from "@voltprotocol/core/CoreV2.sol";
import {VoltRoles} from "@voltprotocol/core/VoltRoles.sol";

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
        assertEq(core.getRoleMemberCount(VoltRoles.PCV_CONTROLLER), 5);

        assertEq(
            core.getRoleMember(VoltRoles.PCV_CONTROLLER, 0),
            addresses.mainnet("PCV_GUARDIAN")
        );
        assertEq(
            core.getRoleMember(VoltRoles.PCV_CONTROLLER, 1),
            addresses.mainnet("PCV_ROUTER")
        );
        assertEq(
            core.getRoleMember(VoltRoles.PCV_CONTROLLER, 2),
            addresses.mainnet("GOVERNOR")
        );
        assertEq(
            core.getRoleMember(VoltRoles.PCV_CONTROLLER, 3),
            addresses.mainnet("PSM_NONCUSTODIAL_DAI")
        );
        assertEq(
            core.getRoleMember(VoltRoles.PCV_CONTROLLER, 4),
            addresses.mainnet("PSM_NONCUSTODIAL_USDC")
        );

        // PCV_MOVER
        assertEq(core.getRoleAdmin(VoltRoles.PCV_MOVER), VoltRoles.GOVERNOR);
        assertEq(core.getRoleMemberCount(VoltRoles.PCV_MOVER), 1);
        assertEq(
            core.getRoleMember(VoltRoles.PCV_MOVER, 0),
            addresses.mainnet("GOVERNOR")
        );

        // PCV_DEPOSIT_ROLE
        assertEq(core.getRoleAdmin(VoltRoles.PCV_DEPOSIT), VoltRoles.GOVERNOR);
        assertEq(core.getRoleMemberCount(VoltRoles.PCV_DEPOSIT), 6);
        assertEq(
            core.getRoleMember(VoltRoles.PCV_DEPOSIT, 0),
            addresses.mainnet("PCV_DEPOSIT_MORPHO_COMPOUND_DAI")
        );
        assertEq(
            core.getRoleMember(VoltRoles.PCV_DEPOSIT, 1),
            addresses.mainnet("PCV_DEPOSIT_MORPHO_COMPOUND_USDC")
        );
        assertEq(
            core.getRoleMember(VoltRoles.PCV_DEPOSIT, 2),
            addresses.mainnet("PCV_DEPOSIT_MORPHO_AAVE_DAI")
        );
        assertEq(
            core.getRoleMember(VoltRoles.PCV_DEPOSIT, 3),
            addresses.mainnet("PCV_DEPOSIT_MORPHO_AAVE_USDC")
        );
        assertEq(
            core.getRoleMember(VoltRoles.PCV_DEPOSIT, 4),
            addresses.mainnet("PCV_DEPOSIT_EULER_DAI")
        );
        assertEq(
            core.getRoleMember(VoltRoles.PCV_DEPOSIT, 5),
            addresses.mainnet("PCV_DEPOSIT_EULER_USDC")
        );

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
        assertEq(core.getRoleMemberCount(VoltRoles.GUARDIAN), 3);
        assertEq(
            core.getRoleMember(VoltRoles.GUARDIAN, 0),
            addresses.mainnet("PCV_GUARDIAN")
        );
        assertEq(
            core.getRoleMember(VoltRoles.GUARDIAN, 1),
            addresses.mainnet("GOVERNOR") // team multisig
        );
        assertEq(
            core.getRoleMember(VoltRoles.GUARDIAN, 2),
            addresses.mainnet("COMPOUND_BAD_DEBT_SENTINEL")
        );

        // PSM_MINTER_ROLE
        assertEq(
            core.getRoleAdmin(VoltRoles.PSM_MINTER),
            VoltRoles.GOVERNOR
        );
        assertEq(
            core.getRoleMemberCount(
                VoltRoles.PSM_MINTER
            ),
            2
        );
        assertEq(
            core.getRoleMember(VoltRoles.PSM_MINTER, 0),
            addresses.mainnet("PSM_NONCUSTODIAL_DAI")
        );
        assertEq(
            core.getRoleMember(VoltRoles.PSM_MINTER, 1),
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
            addresses.mainnet("PCV_ORACLE")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 2),
            addresses.mainnet("PCV_DEPOSIT_MORPHO_COMPOUND_DAI")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 3),
            addresses.mainnet("PCV_DEPOSIT_MORPHO_COMPOUND_USDC")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 4),
            addresses.mainnet("GLOBAL_RATE_LIMITED_MINTER")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 5),
            addresses.mainnet("PCV_ROUTER")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 6),
            addresses.mainnet("PCV_GUARDIAN")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 7),
            addresses.mainnet("PSM_NONCUSTODIAL_DAI")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 8),
            addresses.mainnet("PSM_NONCUSTODIAL_USDC")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 9),
            addresses.mainnet("PCV_DEPOSIT_EULER_DAI")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 10),
            addresses.mainnet("PCV_DEPOSIT_EULER_USDC")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 11),
            addresses.mainnet("PCV_DEPOSIT_MORPHO_AAVE_DAI")
        );
        assertEq(
            core.getRoleMember(VoltRoles.LOCKER, 12),
            addresses.mainnet("PCV_DEPOSIT_MORPHO_AAVE_USDC")
        );

        // MINTER
        assertEq(core.getRoleAdmin(VoltRoles.MINTER), VoltRoles.GOVERNOR);
        assertEq(core.getRoleMemberCount(VoltRoles.MINTER), 1);
        assertEq(
            core.getRoleMember(VoltRoles.MINTER, 0),
            addresses.mainnet("GLOBAL_RATE_LIMITED_MINTER")
        );
    }
}
