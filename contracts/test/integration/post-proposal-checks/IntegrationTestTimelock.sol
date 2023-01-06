// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {PostProposalCheck} from "./PostProposalCheck.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract IntegrationTestTimelock is PostProposalCheck {
    // Validate timelock role assignments
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

    // Validate that the team multisig can propose to timelock and
    // that anyone can execute after the delay
    function testMultisigProposesTimelock() public {
        TimelockController timelockController = TimelockController(
            payable(addresses.mainnet("TIMELOCK_CONTROLLER"))
        );
        uint256 ethSendAmount = 100 ether;
        vm.deal(address(timelockController), ethSendAmount);

        assertEq(address(timelockController).balance, ethSendAmount); /// starts with 0 balance

        bytes memory data = "";
        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(0);
        address recipient = address(100);

        vm.prank(addresses.mainnet("GOVERNOR")); // team multisig
        timelockController.schedule(
            recipient,
            ethSendAmount,
            data,
            predecessor,
            salt,
            86400
        );
        bytes32 id = timelockController.hashOperation(
            recipient,
            ethSendAmount,
            data,
            predecessor,
            salt
        );

        uint256 startingEthBalance = recipient.balance;

        assertTrue(!timelockController.isOperationDone(id)); /// operation is not done
        assertTrue(!timelockController.isOperationReady(id)); /// operation is not ready

        vm.warp(block.timestamp + timelockController.getMinDelay());
        assertTrue(timelockController.isOperationReady(id)); /// operation is ready

        timelockController.execute(
            recipient,
            ethSendAmount,
            data,
            predecessor,
            salt
        );

        assertTrue(timelockController.isOperationDone(id)); /// operation is done

        assertEq(address(timelockController).balance, 0);
        assertEq(recipient.balance, ethSendAmount + startingEthBalance); /// assert receiver received their eth
    }
}
