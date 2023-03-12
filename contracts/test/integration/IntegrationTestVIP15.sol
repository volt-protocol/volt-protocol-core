// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {vip15} from "./vip/vip15.sol";
import {ICore} from "../../core/ICore.sol";
import {IVolt} from "../../volt/Volt.sol";
import {IPCVDeposit} from "../../pcv/IPCVDeposit.sol";
import {IPCVGuardian} from "../../pcv/IPCVGuardian.sol";
import {PriceBoundPSM} from "../../peg/PriceBoundPSM.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {TimelockSimulation} from "./utils/TimelockSimulation.sol";

contract IntegrationTestVIP14 is TimelockSimulation, vip15 {
    using SafeCast for *;

    IPCVGuardian private immutable mainnetPCVGuardian =
        IPCVGuardian(MainnetAddresses.PCV_GUARDIAN);

    function setUp() public {
        mainnetSetup();
        simulate(
            getMainnetProposal(),
            TimelockController(payable(MainnetAddresses.TIMELOCK_CONTROLLER)),
            mainnetPCVGuardian,
            MainnetAddresses.GOVERNOR,
            MainnetAddresses.EOA_1,
            vm,
            false
        );
        mainnetValidate();

        vm.label(address(pcvGuardian), "PCV Guardian");
    }

    function testSkimFailsPaused() public {
        vm.expectRevert("Pausable: paused");
    }

    function testDripFailsPaused() public {
        vm.expectRevert("Pausable: paused");
    }

    function testMintFailsPausedDai() public {
        vm.expectRevert("Pausable: paused");
    }

    function testMintFailsPausedUsdc() public {}
}
