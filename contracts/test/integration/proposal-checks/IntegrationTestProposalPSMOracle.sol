// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Test} from "@forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Addresses} from "../../proposals/Addresses.sol";
import {TestProposals} from "../../proposals/TestProposals.sol";

import {IOracleRef} from "../../../refs/IOracleRef.sol";
import {IOracleRefV2} from "../../../refs/IOracleRefV2.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";

contract IntegrationTestProposalPSMOracle is Test {
    function setUp() public {}

    function testPsmOracle() public {
        Addresses addresses = new Addresses();
        TestProposals proposals = new TestProposals();
        proposals.setUp();
        proposals.setDebug(false);

        // If one of the proposals skip PSM verification,
        // do not perform verification. This is useful when interface
        // change on the PSMs or if the oracle logic is changed.
        uint256 nProposals = proposals.nProposals();
        bool doTest = true;
        for (uint256 i = 0; i < nProposals; i++) {
            if (proposals.proposals(i).SKIP_PSM_ORACLE_TEST()) {
                doTest = false;
            }
        }
        if (!doTest) return;

        // Read oracles pre-proposals
        uint256 oraclePriceBeforeDaiPSM = IOracleRef(
            addresses.mainnet("VOLT_DAI_PSM")
        ).readOracle().value;
        uint256 oraclePricesBeforeUsdcPSM = IOracleRef(
            addresses.mainnet("VOLT_USDC_PSM")
        ).readOracle().value;

        // Run all pending proposals
        proposals.testProposals();
        addresses = proposals.addresses();

        // Read oracles post-proposals
        uint256 oraclePricesAfterDaiPSM = IOracleRefV2(
            addresses.mainnet("PSM_DAI")
        ).readOracle();
        uint256 oraclePricesAfterUsdcPSM = IOracleRefV2(
            addresses.mainnet("PSM_USDC")
        ).readOracle();

        // Check oracle values are the same
        assertEq(
            oraclePriceBeforeDaiPSM,
            oraclePricesAfterDaiPSM,
            "PSM Oracle value changed (DAI old->DAI new)"
        );
        assertEq(
            oraclePriceBeforeDaiPSM / 1e12,
            oraclePricesAfterUsdcPSM,
            "PSM Oracle value changed (DAI old->USDC new)"
        );
        assertEq(
            oraclePricesBeforeUsdcPSM,
            oraclePricesAfterDaiPSM,
            "PSM Oracle value changed (USDC old->DAI new)"
        );
        assertEq(
            oraclePricesBeforeUsdcPSM / 1e12,
            oraclePricesAfterUsdcPSM,
            "PSM Oracle value changed (USDC old->USDC new)"
        );
    }

    function testPSMSameMint() public {
        // Init
        Addresses addresses = new Addresses();
        PegStabilityModule psm = PegStabilityModule(
            addresses.mainnet("PSM_USDC")
        );
        IERC20 volt = IERC20(addresses.mainnet("VOLT"));
        IERC20 token = IERC20(addresses.mainnet("USDC"));
        uint256 amountTokens = 100e6;

        // Read pre-proposal VOLT minted for a known amount of USDC
        deal(address(token), address(this), amountTokens);
        token.approve(address(psm), amountTokens);
        psm.mint(address(this), amountTokens, 0);
        uint256 receivedVoltPreProposal = volt.balanceOf(address(this));
        volt.transfer(address(psm), receivedVoltPreProposal);

        // Run all pending proposals
        TestProposals proposals = new TestProposals();
        proposals.setUp();
        proposals.setDebug(false); // no prints
        proposals.testProposals();
        addresses = proposals.addresses(); // get post-proposal addresses

        // Use post-proposal contracts if they have been migrated
        psm = PegStabilityModule(addresses.mainnet("PSM_USDC"));
        volt = IERC20(addresses.mainnet("VOLT"));
        token = IERC20(addresses.mainnet("USDC"));

        // Read post-proposal VOLT minted for a known amount of USDC
        deal(address(token), address(this), amountTokens);
        token.approve(address(psm), amountTokens);
        psm.mint(address(this), amountTokens, 0);
        uint256 receivedVoltPostProposal = volt.balanceOf(address(this));
        volt.transfer(address(psm), receivedVoltPostProposal);

        // Check amounts of VOLT minted for the same amount of USDC in
        // are the same before & after proposals executions
        // Tolerate 0.05% difference because the proposals might fast-forward
        // in time and that will make the oracle prices progress.
        uint256 toleratedDiff = (5 * receivedVoltPreProposal) / 10_000;
        assertGt(
            receivedVoltPreProposal,
            receivedVoltPostProposal - toleratedDiff
        );
    }
}
