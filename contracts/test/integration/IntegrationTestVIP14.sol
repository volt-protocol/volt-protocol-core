// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {vip14} from "./vip/vip14.sol";
import {ICore} from "../../core/ICore.sol";
import {IVolt} from "../../volt/Volt.sol";
import {IPCVDeposit} from "../../pcv/IPCVDeposit.sol";
import {IPCVGuardian} from "../../pcv/IPCVGuardian.sol";
import {PriceBoundPSM} from "../../peg/PriceBoundPSM.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {TimelockSimulation} from "./utils/TimelockSimulation.sol";

contract IntegrationTestVIP14 is TimelockSimulation, vip14 {
    using SafeCast for *;

    IPCVGuardian private immutable mainnetPCVGuardian =
        IPCVGuardian(MainnetAddresses.PCV_GUARDIAN);

    /// @notice scaling factor for USDC
    uint256 public constant USDC_SCALING_FACTOR = 1e12;

    uint256 public constant targetDaiBalance = 100_000e18;

    uint256 public constant targetUsdcBalance = 100_000e6;

    address private governor = MainnetAddresses.GOVERNOR;

    IERC20 public comp = IERC20(MainnetAddresses.COMP);

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

        vm.label(address(usdcDeposit), "USDC Deposit");
        vm.label(address(daiDeposit), "DAI Deposit");
        vm.label(address(allocator), "Allocator");
        vm.label(address(pcvGuardian), "PCV Guardian");
        vm.label(address(MainnetAddresses.VOLT_DAI_PSM), "VOLT_DAI_PSM");
        vm.label(address(MainnetAddresses.VOLT_USDC_PSM), "VOLT_USDC_PSM");
    }

    function testSkimDaiToMorphoDeposit() public {
        vm.prank(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        IERC20(dai).transfer(
            MainnetAddresses.VOLT_DAI_PSM,
            targetDaiBalance * 2
        );
        assertTrue(
            IERC20(dai).balanceOf(MainnetAddresses.VOLT_DAI_PSM) >=
                targetDaiBalance * 2
        );

        uint256 daiSurplus = IERC20(dai).balanceOf(
            MainnetAddresses.VOLT_DAI_PSM
        ) - targetDaiBalance;

        uint256 startingDaiDepositBalance = daiDeposit.balance();

        allocator.skim(address(daiDeposit));

        uint256 endingDaiDepositBalance = daiDeposit.balance();

        assertApproxEq(
            (startingDaiDepositBalance + daiSurplus).toInt256(),
            endingDaiDepositBalance.toInt256(),
            0
        );

        assertEq(
            IERC20(dai).balanceOf(MainnetAddresses.VOLT_DAI_PSM),
            targetDaiBalance
        );
    }

    function testSkimUsdcToMorphoDeposit() public {
        vm.prank(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        IERC20(usdc).transfer(
            MainnetAddresses.VOLT_USDC_PSM,
            targetUsdcBalance * 2
        );
        assertTrue(
            IERC20(usdc).balanceOf(MainnetAddresses.VOLT_USDC_PSM) >=
                targetUsdcBalance * 2
        );

        uint256 usdcSurplus = IERC20(usdc).balanceOf(
            MainnetAddresses.VOLT_USDC_PSM
        ) - targetUsdcBalance;

        uint256 startingUsdcDepositBalance = usdcDeposit.balance();

        allocator.skim(address(usdcDeposit));

        uint256 endingUsdcDepositBalance = usdcDeposit.balance();

        assertApproxEq(
            (startingUsdcDepositBalance + usdcSurplus).toInt256(),
            endingUsdcDepositBalance.toInt256(),
            0
        );
        assertEq(
            IERC20(usdc).balanceOf(MainnetAddresses.VOLT_USDC_PSM),
            targetUsdcBalance
        );
    }

    function testDripUsdcToPsm() public {
        vm.prank(MainnetAddresses.EOA_1);
        mainnetPCVGuardian.withdrawAllToSafeAddress(
            MainnetAddresses.VOLT_USDC_PSM
        );

        assertTrue(
            IPCVDeposit(MainnetAddresses.VOLT_USDC_PSM).balance() <= 1e6
        );

        uint256 startingDepositBalance = usdcDeposit.balance();

        allocator.drip(address(usdcDeposit));

        uint256 endingDepositBalance = usdcDeposit.balance();

        assertApproxEq(
            (startingDepositBalance - endingDepositBalance).toInt256(),
            targetUsdcBalance.toInt256(),
            0
        );
        assertEq(
            IPCVDeposit(MainnetAddresses.VOLT_USDC_PSM).balance(),
            targetUsdcBalance
        );
    }

    function testDripDaiToPsm() public {
        vm.prank(MainnetAddresses.EOA_1);
        mainnetPCVGuardian.withdrawAllToSafeAddress(
            MainnetAddresses.VOLT_DAI_PSM
        );

        uint256 startingDepositBalance = daiDeposit.balance();

        assertTrue(
            IPCVDeposit(MainnetAddresses.VOLT_DAI_PSM).balance() <= 1e18
        );

        allocator.drip(address(daiDeposit));

        uint256 endingDepositBalance = daiDeposit.balance();

        assertApproxEq(
            (startingDepositBalance - endingDepositBalance).toInt256(),
            targetDaiBalance.toInt256(),
            0
        );
        assertEq(
            IPCVDeposit(MainnetAddresses.VOLT_DAI_PSM).balance(),
            targetDaiBalance
        );
    }

    function testClaimCompRewardsDai() public {
        uint256 startingCompBalance = comp.balanceOf(address(daiDeposit));

        vm.roll(block.number + 100 days / 12);
        daiDeposit.harvest();

        uint256 endingCompBalance = comp.balanceOf(address(daiDeposit));
        assertTrue(endingCompBalance - startingCompBalance != 0);
    }

    function testClaimCompRewardsUsdc() public {
        uint256 startingCompBalance = comp.balanceOf(address(usdcDeposit));

        vm.roll(block.number + 100 days / 12);
        usdcDeposit.harvest();

        uint256 endingCompBalance = comp.balanceOf(address(usdcDeposit));
        assertTrue(endingCompBalance - startingCompBalance != 0);
    }

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
