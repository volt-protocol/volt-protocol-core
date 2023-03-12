//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {Vm} from "./../../unit/utils/Vm.sol";
import {Core} from "../../../core/Core.sol";
import {IVIP} from "./IVIP.sol";
import {DSTest} from "./../../unit/utils/DSTest.sol";
import {PCVDeposit} from "../../../pcv/PCVDeposit.sol";
import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";
import {IPCVDeposit} from "../../../pcv/IPCVDeposit.sol";
import {PriceBoundPSM} from "../../../peg/PriceBoundPSM.sol";
import {VoltSystemOracle} from "../../../oracle/VoltSystemOracle.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {OraclePassThrough} from "../../../oracle/OraclePassThrough.sol";
import {CompoundPCVRouter} from "../../../pcv/compound/CompoundPCVRouter.sol";
import {ITimelockSimulation} from "../utils/ITimelockSimulation.sol";

/// VIP 15
/// This VIP is the first step in Mainnet deprecation. It pauses minting
/// on the Mainnet PSMs and sets the oracle to a constant price oracle
/// that does not compound interest.

/// Deployment Steps
/// 1. deploy volt system oracle

/// Governance Steps
/// 1. connect new oracle to oracle pass through with updated rate
/// 2. disable minting on USDC PSM
/// 3. disable minting on DAI PSM

contract vip15 is DSTest, IVIP {
    using SafeERC20 for IERC20;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    ITimelockSimulation.action[] private mainnetProposal;

    VoltSystemOracle public oracle;
    /// = VoltSystemOracle(MainnetAddresses.VOLT_SYSTEM_ORACLE_0_BIPS); TODO hardcode this once deployed

    uint256 public startPrice = 1062988312906423708;

    uint256 public constant monthlyChangeRateBasisPoints = 0;

    PCVGuardian public immutable pcvGuardian =
        PCVGuardian(MainnetAddresses.PCV_GUARDIAN);

    OraclePassThrough public immutable opt =
        OraclePassThrough(MainnetAddresses.ORACLE_PASS_THROUGH);

    constructor() {
        if (block.chainid != 1) {
            return;
        }

        oracle = new VoltSystemOracle(
            monthlyChangeRateBasisPoints,
            block.timestamp,
            startPrice
        );

        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.ORACLE_PASS_THROUGH,
                arguments: abi.encodeWithSignature(
                    "updateScalingPriceOracle(address)",
                    address(oracle)
                ),
                description: "Point Mainnet Oracle Pass Through to 0 basis point Volt System Oracle"
            })
        );
        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.VOLT_USDC_PSM,
                arguments: abi.encodeWithSignature("pauseMint()"),
                description: "Pause minting on USDC PSM on Mainnet"
            })
        );
        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.VOLT_DAI_PSM,
                arguments: abi.encodeWithSignature("pauseMint()"),
                description: "Pause minting on DAI PSM on Mainnet"
            })
        );
        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.MORPHO_COMPOUND_PCV_ROUTER,
                arguments: abi.encodeWithSignature("pause()"),
                description: "Pause Morpho Compound PCV Router on Mainnet"
            })
        );
    }

    function getMainnetProposal()
        public
        view
        override
        returns (ITimelockSimulation.action[] memory)
    {
        return mainnetProposal;
    }

    function mainnetSetup() public pure override {}

    /// assert oracle pass through is pointing to correct volt system oracle
    function mainnetValidate() public override {
        /// oracle pass through points to new scaling price oracle
        assertEq(
            address(
                OraclePassThrough(MainnetAddresses.ORACLE_PASS_THROUGH)
                    .scalingPriceOracle()
            ),
            address(oracle)
        );
        assertEq(
            oracle.monthlyChangeRateBasisPoints(),
            monthlyChangeRateBasisPoints
        );
        assertEq(oracle.monthlyChangeRateBasisPoints(), 0); /// pause rate updates to Volt on Mainnet
        assertEq(oracle.periodStartTime(), block.timestamp - 1 days);
        assertEq(opt.getCurrentOraclePrice(), startPrice);
        assertEq(oracle.oraclePrice(), startPrice);

        /// minting paused
        assertTrue(PriceBoundPSM(MainnetAddresses.VOLT_USDC_PSM).mintPaused());
        assertTrue(PriceBoundPSM(MainnetAddresses.VOLT_DAI_PSM).mintPaused());

        /// redemptions enabled
        assertTrue(
            !PriceBoundPSM(MainnetAddresses.VOLT_USDC_PSM).redeemPaused()
        );
        assertTrue(
            !PriceBoundPSM(MainnetAddresses.VOLT_DAI_PSM).redeemPaused()
        );

        assertTrue(PriceBoundPSM(MainnetAddresses.ERC20ALLOCATOR).paused());
        assertTrue(
            PriceBoundPSM(MainnetAddresses.MORPHO_COMPOUND_PCV_ROUTER).paused()
        );
        assertTrue(
            PriceBoundPSM(MainnetAddresses.MORPHO_COMPOUND_DAI_PCV_DEPOSIT)
                .paused()
        );
        assertTrue(
            PriceBoundPSM(MainnetAddresses.MORPHO_COMPOUND_USDC_PCV_DEPOSIT)
                .paused()
        );

        vm.expectRevert("PegStabilityModule: Minting paused");
        PriceBoundPSM(MainnetAddresses.VOLT_USDC_PSM).mint(address(this), 0, 0);

        vm.expectRevert("PegStabilityModule: Minting paused");
        PriceBoundPSM(MainnetAddresses.VOLT_DAI_PSM).mint(address(this), 0, 0);
        vm.warp(block.timestamp + 100 days);

        oracle.compoundInterest();
        assertEq(opt.getCurrentOraclePrice(), startPrice);
        assertEq(oracle.oraclePrice(), startPrice);
    }

    function getArbitrumProposal()
        public
        view
        override
        returns (ITimelockSimulation.action[] memory)
    {}

    /// no-op, nothing to setup
    function arbitrumSetup() public override {
        revert("no arbitrum setup actions");
    }

    function arbitrumValidate() public override {
        revert("no arbitrum validate actions");
    }
}
