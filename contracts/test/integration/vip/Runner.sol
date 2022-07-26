pragma solidity =0.8.13;

import {vip4} from "./vip4.sol";
import {TimelockSimulation} from "../utils/TimelockSimulation.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract Runner is TimelockSimulation, vip4 {
    /// @notice add prints here as new VIP's come online
    function testPrintCalldata() public {
        testPrintScheduleAndExecuteCalldata();
    }

    function testSimulate() public {
        setup();
        simulate(
            getVIP(),
            TimelockController(payable(MainnetAddresses.TIMELOCK_CONTROLLER)),
            MainnetAddresses.GOVERNOR,
            MainnetAddresses.EOA_1,
            vm
        );
    }
}
