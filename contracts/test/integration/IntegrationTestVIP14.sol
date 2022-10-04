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

    IPCVGuardian private immutable mainnetPCVGuardian =
        IPCVGuardian(MainnetAddresses.PCV_GUARDIAN);

    /// @notice scaling factor for USDC
    uint256 public constant USDC_SCALING_FACTOR = 1e12;

    address private governor = MainnetAddresses.GOVERNOR;

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

    function testSwapUsdcToDaiRouter() public {
        uint256 withdrawAmount = usdcDeposit.balance();
        uint256 daiStartingBalance = daiDeposit.balance();

        vm.prank(governor);
        router.swapUsdcForDai(withdrawAmount);

        assertApproxEq(
            daiDeposit.balance().toInt256(),
            (withdrawAmount * USDC_SCALING_FACTOR + daiStartingBalance)
                .toInt256(),
            0
        );

        assertTrue(usdcDeposit.balance() < 1e3); /// assert only dust remains
    }

    function testSwapDaiToUsdcRouter() public {
        uint256 withdrawAmount = daiDeposit.balance();
        uint256 usdcStartingBalance = usdcDeposit.balance();

        vm.prank(governor);
        router.swapDaiForUsdc(withdrawAmount); /// withdraw all balance

        assertApproxEq(
            usdcDeposit.balance().toInt256(),
            (withdrawAmount / USDC_SCALING_FACTOR + usdcStartingBalance)
                .toInt256(),
            0
        );
        assertTrue(daiDeposit.balance() < 1e10); /// assert only dust remains
    }

    function testSwapUsdcToDaiFailsUnauthorized() public {
        uint256 withdrawAmount = usdcDeposit.balance();
        vm.expectRevert("UNAUTHORIZED");
        router.swapUsdcForDai(withdrawAmount);
    }

    function testSwapDaiToUsdcFailsUnauthorized() public {
        uint256 withdrawAmount = daiDeposit.balance();
        vm.expectRevert("UNAUTHORIZED");
        router.swapDaiForUsdc(withdrawAmount);
    }
}
