// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "hardhat/console.sol";

import {Test} from "../../../../forge-std/src/Test.sol";

import {Addresses} from "../../proposals/Addresses.sol";
import {TestProposals} from "../../proposals/TestProposals.sol";

import {CoreV2} from "../../../core/CoreV2.sol";
import {PCVOracle} from "../../../oracle/PCVOracle.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract IntegrationTestProposalNoPCVLeak is Test {
    function setUp() public {}

    function testNoPCVLeak() public {
        // Init
        Addresses addresses = new Addresses();
        PCVOracle pcvOracle = PCVOracle(addresses.mainnet("PCV_ORACLE"));

        // Read pre-proposal PCV
        uint256 totalPcvPreProposal = 0;
        if (address(pcvOracle) != address(0)) {
            (, , totalPcvPreProposal) = pcvOracle.getTotalPcv();
        }

        // Run all pending proposals
        TestProposals proposals = new TestProposals();
        proposals.setUp();
        proposals.setDebug(false); // no prints
        uint256[] memory postProposalVmSnapshots = proposals.testProposals();

        for (uint256 i = 0; i < postProposalVmSnapshots.length; i++) {
            if (proposals.proposals(i).EXPECT_PCV_CHANGE()) {
                continue;
            }

            vm.revertTo(postProposalVmSnapshots[i]);

            addresses = proposals.addresses(); // get post-proposal addresses

            // Read post-proposal PCV
            pcvOracle = PCVOracle(addresses.mainnet("PCV_ORACLE"));
            uint256 totalPcvPostProposal = 0;
            if (address(pcvOracle) != address(0)) {
                (, , totalPcvPostProposal) = pcvOracle.getTotalPcv();
            }

            // Assert no PCV leaked out of the system : check 3 bips leak at most
            string memory errorMessage = string(
                abi.encodePacked(
                    "PCV leak in proposal ",
                    proposals.proposals(i).name()
                )
            );
            assertTrue(
                totalPcvPostProposal >= (totalPcvPreProposal * 9997) / 10000,
                errorMessage
            );
        }
    }
}
