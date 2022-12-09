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
import {CompoundPCVRouter} from "../../../pcv/compound/CompoundPCVRouter.sol";
import {IOraclePassThrough} from "../../../oracle/IOraclePassThrough.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";
import {ITimelockSimulation} from "../utils/ITimelockSimulation.sol";

contract vip16 is DSTest, IVIP {
    using SafeERC20 for IERC20;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    IOraclePassThrough private mainnetOPT =
        IOraclePassThrough(MainnetAddresses.ORACLE_PASS_THROUGH);

    ITimelockSimulation.action[] private arbitrumProposal;
    ITimelockSimulation.action[] private mainnetProposal;

    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");

    constructor() {
        if (block.chainid != 1) {
            arbitrumProposal.push(
                ITimelockSimulation.action({
                    value: 0,
                    target: ArbitrumAddresses.TIMELOCK_CONTROLLER,
                    arguments: abi.encodeWithSignature(
                        "revokeRole(bytes32,address)",
                        PROPOSER_ROLE,
                        ArbitrumAddresses.REVOKED_EOA_3
                    ),
                    description: "Revoke Kassim's proposer role"
                })
            );
            arbitrumProposal.push(
                ITimelockSimulation.action({
                    value: 0,
                    target: ArbitrumAddresses.TIMELOCK_CONTROLLER,
                    arguments: abi.encodeWithSignature(
                        "revokeRole(bytes32,address)",
                        CANCELLER_ROLE,
                        ArbitrumAddresses.REVOKED_EOA_3
                    ),
                    description: "Revoke Kassim's proposer role"
                })
            );

            return;
        }

        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.TIMELOCK_CONTROLLER,
                arguments: abi.encodeWithSignature(
                    "revokeRole(bytes32,address)",
                    PROPOSER_ROLE,
                    MainnetAddresses.REVOKED_EOA_3
                ),
                description: "Revoke Kassim's proposer role"
            })
        );
        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.TIMELOCK_CONTROLLER,
                arguments: abi.encodeWithSignature(
                    "revokeRole(bytes32,address)",
                    CANCELLER_ROLE,
                    MainnetAddresses.REVOKED_EOA_3
                ),
                description: "Revoke Kassim's proposer role"
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

    function mainnetValidate() public override {
        TimelockController tc = TimelockController(
            payable(MainnetAddresses.TIMELOCK_CONTROLLER)
        );

        assertTrue(!tc.hasRole(PROPOSER_ROLE, MainnetAddresses.REVOKED_EOA_3));
        assertTrue(!tc.hasRole(CANCELLER_ROLE, MainnetAddresses.REVOKED_EOA_3));
    }

    function getArbitrumProposal()
        public
        view
        override
        returns (ITimelockSimulation.action[] memory)
    {
        return arbitrumProposal;
    }

    function arbitrumSetup() public pure override {}

    function arbitrumValidate() public override {
        TimelockController tc = TimelockController(
            payable(ArbitrumAddresses.TIMELOCK_CONTROLLER)
        );

        assertTrue(!tc.hasRole(PROPOSER_ROLE, ArbitrumAddresses.REVOKED_EOA_3));
        assertTrue(
            !tc.hasRole(CANCELLER_ROLE, ArbitrumAddresses.REVOKED_EOA_3)
        );
    }
}
