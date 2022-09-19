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
import {OraclePassThrough} from "../../../oracle/OraclePassThrough.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";
import {ITimelockSimulation} from "../utils/ITimelockSimulation.sol";
import {ERC20CompoundPCVDeposit} from "../../../pcv/compound/ERC20CompoundPCVDeposit.sol";

contract vip12 is DSTest, IVIP {
    using SafeERC20 for IERC20;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    address private fei = MainnetAddresses.FEI;
    address private core = MainnetAddresses.CORE;

    OraclePassThrough private mainnetOPT =
        OraclePassThrough(MainnetAddresses.ORACLE_PASS_THROUGH);

    ITimelockSimulation.action[] private mainnetProposal;

    constructor() {
        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.CORE,
                arguments: abi.encodeWithSignature(
                    "grantPCVController(address)"
                    // MainnetAddresses.COMPOUND_PCV_ROUTER TODO on deployment
                ),
                description: "Grant PCV Controller to Compound PCV Router"
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

    /// TODO on deployment
    /// assert compound pcv router has pcv controller role
    /// assert all variables are correclty set in compound pcv router
    function mainnetValidate() public override {}

    function getArbitrumProposal()
        public
        view
        override
        returns (ITimelockSimulation.action[] memory)
    {
        revert("No Arbitrum proposal");
    }

    function arbitrumSetup() public override {
        revert("No Arbitrum proposal");
    }

    /// assert oracle pass through is pointing to correct volt system oracle
    function arbitrumValidate() public override {
        revert("No Arbitrum proposal");
    }
}
