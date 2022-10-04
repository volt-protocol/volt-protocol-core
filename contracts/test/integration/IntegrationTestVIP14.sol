// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ICore} from "../../core/ICore.sol";
import {IVolt} from "../../volt/Volt.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {vip14} from "./vip/vip14.sol";
import {TimelockSimulation} from "./utils/TimelockSimulation.sol";
import {PriceBoundPSM} from "../../peg/PriceBoundPSM.sol";
import {IPCVGuardian} from "../../pcv/IPCVGuardian.sol";

contract IntegrationTestVIP14 is TimelockSimulation, vip14 {
    using SafeCast for *;
    PriceBoundPSM private psm = PriceBoundPSM(MainnetAddresses.VOLT_DAI_PSM);

    ICore private core = ICore(MainnetAddresses.CORE);
    IERC20 dai = IERC20(MainnetAddresses.DAI);
    IVolt volt = IVolt(MainnetAddresses.VOLT);

    uint256 public constant mintAmount = type(uint80).max;

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
    }

    function testSkimDaiToMorphoDeposit() public {}

    function testSkimUsdcToMorphoDeposit() public {}

    function testDripUsdcToPsm() public {}

    function testDripDaiToPsm() public {}

    function testClaimCompRewardsDai() public {}

    function testClaimCompRewardsUsdc() public {}
}
