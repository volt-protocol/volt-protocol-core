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
            totalPcvPreProposal = pcvOracle.getTotalPcv();
        }

        // Run all pending proposals
        TestProposals proposals = new TestProposals();
        proposals.setUp();
        proposals.setDebug(false); // no prints
        uint256[] memory postProposalVmSnapshots = proposals.testProposals();
        addresses = proposals.addresses(); // get post-proposal addresses

        // Sum the tolerated percentages of change
        uint256 expectedPcvChangePercent = 0;
        for (uint256 i = 0; i < postProposalVmSnapshots.length; i++) {
            expectedPcvChangePercent += proposals
                .proposals(i)
                .EXPECT_PCV_CHANGE();
        }

        // Read post-proposal PCV
        pcvOracle = PCVOracle(addresses.mainnet("PCV_ORACLE"));
        uint256 totalPcvPostProposal = 0;
        if (address(pcvOracle) != address(0)) {
            totalPcvPostProposal = pcvOracle.getTotalPcv();
        }

        // Check pcv leak
        uint256 toleratedPcvLoss = (expectedPcvChangePercent *
            totalPcvPreProposal) / 1e18;
        int256 proposalLeakedPcv = int256(totalPcvPreProposal) -
            int256(totalPcvPostProposal);
        if (proposalLeakedPcv >= int256(toleratedPcvLoss)) {
            emit log_named_uint(
                "expectedPcvChangePercent ",
                expectedPcvChangePercent
            );
            emit log_named_uint(
                "totalPcvPreProposal      ",
                totalPcvPreProposal
            );
            emit log_named_uint("toleratedPcvLoss         ", toleratedPcvLoss);
            emit log_named_uint(
                "totalPcvPostProposal     ",
                totalPcvPostProposal
            );
            emit log_named_int("proposalLeakedPcv        ", proposalLeakedPcv);
        }
        assertTrue(
            proposalLeakedPcv < int256(toleratedPcvLoss),
            "PCV Leak in proposals"
        );
    }
}
