// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Test} from "../../../../forge-std/src/Test.sol";

import {Addresses} from "../../proposals/Addresses.sol";
import {TestProposals} from "../../proposals/TestProposals.sol";

import {IOracleRef} from "../../../refs/IOracleRef.sol";
import {IOracleRefV2} from "../../../refs/IOracleRefV2.sol";

contract IntegrationTestProposalPSMOracle is Test {
    function setUp() public {}

    function testPsmOracle() public {
        Addresses addresses = new Addresses();

        // Read oracles pre-proposals
        uint256 oraclePriceBeforeDaiPSM = IOracleRef(
            addresses.mainnet("VOLT_DAI_PSM")
        ).readOracle().value;
        uint256 oraclePricesBeforeUsdcPSM = IOracleRef(
            addresses.mainnet("VOLT_USDC_PSM")
        ).readOracle().value;

        // Run all pending proposals
        TestProposals proposals = new TestProposals();
        proposals.setUp();
        proposals.setDebug(false);
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
        require(
            oraclePriceBeforeDaiPSM == oraclePricesAfterDaiPSM,
            "PSM Oracle value changed (DAI old->DAI new)"
        );
        require(
            oraclePriceBeforeDaiPSM / 1e12 == oraclePricesAfterUsdcPSM,
            "PSM Oracle value changed (DAI old->USDC new)"
        );
        require(
            oraclePricesBeforeUsdcPSM == oraclePricesAfterDaiPSM,
            "PSM Oracle value changed (USDC old->DAI new)"
        );
        require(
            oraclePricesBeforeUsdcPSM / 1e12 == oraclePricesAfterUsdcPSM,
            "PSM Oracle value changed (USDC old->USDC new)"
        );
    }
}
