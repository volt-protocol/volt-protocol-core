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
import {VoltSystemOracle} from "../../../oracle/VoltSystemOracle.sol";
import {ArbitrumAddresses} from "../fixtures/ArbitrumAddresses.sol";
import {OraclePassThrough} from "../../../oracle/OraclePassThrough.sol";
import {CompoundPCVRouter} from "../../../pcv/compound/CompoundPCVRouter.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";
import {ITimelockSimulation} from "../utils/ITimelockSimulation.sol";

/// VIP 14-A
/// This VIP is the first step in Arbitrum deprecation. It pauses minting
/// on the Arbitrum PSM and sets the oracle to a constant price oracle
/// that does not compound interest.

/// Deployment Steps
/// 1. deploy volt system oracle

/// Governance Steps
/// 1. connect new oracle to oracle pass through with updated rate
/// 2. disable minting on USDC PSM
/// 3. disable minting on DAI PSM

contract vip14a is DSTest, IVIP {
    using SafeERC20 for IERC20;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    ITimelockSimulation.action[] private arbitrumProposal;

    VoltSystemOracle public oracle =
        VoltSystemOracle(ArbitrumAddresses.VOLT_SYSTEM_ORACLE_0_BIPS);

    uint256 public constant startTime = 1665681823;
    uint256 public startPrice = 1056672647567682146;

    uint256 public constant monthlyChangeRateBasisPoints = 0;

    PCVGuardian public immutable pcvGuardian =
        PCVGuardian(ArbitrumAddresses.PCV_GUARDIAN);

    OraclePassThrough public immutable opt =
        OraclePassThrough(ArbitrumAddresses.ORACLE_PASS_THROUGH);

    constructor() {
        if (block.chainid == 1) {
            return;
        }

        arbitrumProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: ArbitrumAddresses.ORACLE_PASS_THROUGH,
                arguments: abi.encodeWithSignature(
                    "updateScalingPriceOracle(address)",
                    address(oracle)
                ),
                description: "Point Arbitrum Oracle Pass Through to 0 basis point Volt System Oracle"
            })
        );
        arbitrumProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: ArbitrumAddresses.VOLT_USDC_PSM,
                arguments: abi.encodeWithSignature("pauseMint()"),
                description: "Pause minting on USDC PSM on Arbitrum"
            })
        );
        arbitrumProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: ArbitrumAddresses.VOLT_DAI_PSM,
                arguments: abi.encodeWithSignature("pauseMint()"),
                description: "Pause minting on DAI PSM on Arbitrum"
            })
        );
    }

    function getMainnetProposal()
        public
        view
        override
        returns (ITimelockSimulation.action[] memory)
    {}

    function mainnetSetup() public pure override {
        revert("no mainnet setup actions");
    }

    function mainnetValidate() public pure override {
        revert("no mainnet validate actions");
    }

    function getArbitrumProposal()
        public
        view
        override
        returns (ITimelockSimulation.action[] memory)
    {
        return arbitrumProposal;
    }

    /// no-op, nothing to setup
    function arbitrumSetup() public override {}

    /// assert oracle pass through is pointing to correct volt system oracle
    function arbitrumValidate() public override {
        /// oracle pass through points to new scaling price oracle
        assertEq(
            address(
                OraclePassThrough(ArbitrumAddresses.ORACLE_PASS_THROUGH)
                    .scalingPriceOracle()
            ),
            address(oracle)
        );
        assertEq(
            oracle.monthlyChangeRateBasisPoints(),
            monthlyChangeRateBasisPoints
        );
        assertEq(oracle.monthlyChangeRateBasisPoints(), 0); /// pause rate updates to Volt on Arbitrum
        assertEq(oracle.periodStartTime(), startTime);
        assertEq(opt.getCurrentOraclePrice(), startPrice);
        assertEq(oracle.oraclePrice(), startPrice);

        assertTrue(
            PegStabilityModule(ArbitrumAddresses.VOLT_USDC_PSM).mintPaused()
        );
        assertTrue(
            PegStabilityModule(ArbitrumAddresses.VOLT_DAI_PSM).mintPaused()
        );

        vm.expectRevert("PegStabilityModule: Minting paused");
        PegStabilityModule(ArbitrumAddresses.VOLT_USDC_PSM).mint(
            address(this),
            0,
            0
        );

        vm.expectRevert("PegStabilityModule: Minting paused");
        PegStabilityModule(ArbitrumAddresses.VOLT_DAI_PSM).mint(
            address(this),
            0,
            0
        );
        vm.warp(block.timestamp + 100 days);

        oracle.compoundInterest();
        assertEq(opt.getCurrentOraclePrice(), startPrice);
        assertEq(oracle.oraclePrice(), startPrice);
    }
}
