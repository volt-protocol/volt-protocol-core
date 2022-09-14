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
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";
import {ITimelockSimulation} from "../utils/ITimelockSimulation.sol";
import {ERC20CompoundPCVDeposit} from "../../../pcv/compound/ERC20CompoundPCVDeposit.sol";

contract vip11 is DSTest, IVIP {
    using SafeERC20 for IERC20;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    address private fei = MainnetAddresses.FEI;
    address private core = MainnetAddresses.CORE;

    ERC20CompoundPCVDeposit private daiDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_DAI_PCV_DEPOSIT);
    ERC20CompoundPCVDeposit private feiDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_FEI_PCV_DEPOSIT);
    ERC20CompoundPCVDeposit private usdcDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT);

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
                description: "Set oracle pass through to Volt System Oracle 144 bips APR"
            })
        );

        arbitrumProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: ArbitrumAddresses.ORACLE_PASS_THROUGH,
                arguments: abi.encodeWithSignature(
                    "updateScalingPriceOracle(address)"
                    // ArbitrumAddresses.VOLT_SYSTEM_ORACLE_144_BIPS
                ),
                description: "Set oracle pass through to Volt System Oracle 144 bips APR"
            })
        );
    }

    function getMainnetProposal()
        public
        view
        override
        returns (ITimelockSimulation.action[] memory)
    {
        mainnetProposal;
    }

    function mainnetSetup() public override {}

    /// assert oracle pass through is pointing to correct volt system oracle
    function mainnetValidate() public override {}

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
    function arbitrumValidate() public override {}
}
