pragma solidity =0.8.13;

import {vip4} from "./vip4.sol";
import {TimelockSimulation} from "../utils/TimelockSimulation.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {ArbitrumAddresses} from "../fixtures/ArbitrumAddresses.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @dev test harness for running and simulating VOLT Improvement Proposals
contract Runner is TimelockSimulation, vip4 {
    /// remove all function calls inside testProposal and don't inherit the VIP
    /// once the proposal is live and passed
    function testProposalMainnet() public {
        mainnetSetup();
        simulate(
            getMainnetProposal(),
            TimelockController(payable(MainnetAddresses.TIMELOCK_CONTROLLER)),
            MainnetAddresses.GOVERNOR,
            MainnetAddresses.EOA_1,
            vm
        );
        mainnetValidate();
    }

    function testProposalArbitrum() public {
        arbitrumSetup();
        simulate(
            getArbitrumProposal(),
            TimelockController(payable(ArbitrumAddresses.TIMELOCK_CONTROLLER)),
            ArbitrumAddresses.GOVERNOR,
            ArbitrumAddresses.EOA_1,
            vm
        );
        arbitrumValidate();
    }
}
