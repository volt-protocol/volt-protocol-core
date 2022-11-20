//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {Vm} from "./../../unit/utils/Vm.sol";
import {Core} from "../../../core/Core.sol";
import {IVIP} from "./IVIP.sol";
import {DSTest} from "./../../unit/utils/DSTest.sol";
import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {ArbitrumAddresses} from "../fixtures/ArbitrumAddresses.sol";
import {IOraclePassThrough} from "../../../oracle/IOraclePassThrough.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";
import {ITimelockSimulation} from "../utils/ITimelockSimulation.sol";
import {ERC20CompoundPCVDeposit} from "../../../pcv/compound/ERC20CompoundPCVDeposit.sol";

contract vip11 is DSTest, IVIP {
    using SafeERC20 for IERC20;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    address private fei = MainnetAddresses.FEI;
    address private core = MainnetAddresses.CORE;

    IOraclePassThrough private mainnetOPT =
        IOraclePassThrough(MainnetAddresses.ORACLE_PASS_THROUGH);
    IOraclePassThrough private arbitrumOPT =
        IOraclePassThrough(ArbitrumAddresses.ORACLE_PASS_THROUGH);

    ITimelockSimulation.action[] private mainnetProposal;

    ITimelockSimulation.action[] private arbitrumProposal;

    constructor() {
        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.ORACLE_PASS_THROUGH,
                arguments: abi.encodeWithSignature(
                    "updateScalingPriceOracle(address)",
                    MainnetAddresses.VOLT_SYSTEM_ORACLE_144_BIPS
                ),
                description: "Set Volt System Oracle on Oracle Pass Through"
            })
        );

        arbitrumProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: ArbitrumAddresses.ORACLE_PASS_THROUGH,
                arguments: abi.encodeWithSignature(
                    "updateScalingPriceOracle(address)",
                    ArbitrumAddresses.VOLT_SYSTEM_ORACLE_144_BIPS
                ),
                description: "Set Volt System Oracle on Oracle Pass Through"
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

    function mainnetSetup() public override {}

    /// assert oracle pass through is pointing to correct volt system oracle
    function mainnetValidate() public override {
        assertEq(
            address(mainnetOPT.scalingPriceOracle()),
            MainnetAddresses.VOLT_SYSTEM_ORACLE_144_BIPS
        );
    }

    function getArbitrumProposal()
        public
        view
        override
        returns (ITimelockSimulation.action[] memory)
    {
        return arbitrumProposal;
    }

    function arbitrumSetup() public override {}

    /// assert oracle pass through is pointing to correct volt system oracle
    function arbitrumValidate() public override {
        assertEq(
            address(arbitrumOPT.scalingPriceOracle()),
            ArbitrumAddresses.VOLT_SYSTEM_ORACLE_144_BIPS
        );
    }
}
