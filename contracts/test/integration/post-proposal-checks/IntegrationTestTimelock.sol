// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {PostProposalCheck} from "./PostProposalCheck.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract IntegrationTestTimelock is PostProposalCheck {
    function testMainnetTimelockRoles() public {
        TimelockController timelockController = TimelockController(
            payable(addresses.mainnet("TIMELOCK_CONTROLLER"))
        );
        bytes32 EXECUTOR_ROLE = timelockController.EXECUTOR_ROLE();
        bytes32 CANCELLER_ROLE = timelockController.CANCELLER_ROLE();
        bytes32 PROPOSER_ROLE = timelockController.PROPOSER_ROLE();

        assertTrue(timelockController.hasRole(EXECUTOR_ROLE, address(0))); /// role open
        assertTrue(
            timelockController.hasRole(
                CANCELLER_ROLE,
                addresses.mainnet("GOVERNOR")
            )
        );
        assertTrue(
            timelockController.hasRole(
                PROPOSER_ROLE,
                addresses.mainnet("GOVERNOR")
            )
        );
        assertTrue(!timelockController.hasRole(CANCELLER_ROLE, address(0))); /// role closed
        assertTrue(!timelockController.hasRole(PROPOSER_ROLE, address(0))); /// role closed
    }
}
