//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "../unit/utils/Vm.sol";
import {Core} from "../../core/Core.sol";
import {vip10} from "./vip/vip10.sol";
import {IVolt} from "../../volt/IVolt.sol";
import {DSTest} from "../unit/utils/DSTest.sol";
import {IDSSPSM} from "../../pcv/maker/IDSSPSM.sol";
import {Constants} from "../../Constants.sol";
import {PCVDeposit} from "../../pcv/PCVDeposit.sol";
import {PCVGuardian} from "../../pcv/PCVGuardian.sol";
import {ERC20Allocator} from "../../pcv/utils/ERC20Allocator.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {TimelockSimulation} from "./utils/TimelockSimulation.sol";
import {PegStabilityModule} from "../../peg/PegStabilityModule.sol";
import {ERC20CompoundPCVDeposit} from "../../pcv/compound/ERC20CompoundPCVDeposit.sol";

import "hardhat/console.sol";

contract IntegrationTestERC20Allocator is DSTest {
    using SafeCast for *;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    PCVGuardian private immutable mainnetPCVGuardian =
        PCVGuardian(MainnetAddresses.PCV_GUARDIAN);
    ERC20CompoundPCVDeposit private daiDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_DAI_PCV_DEPOSIT);
    ERC20CompoundPCVDeposit private usdcDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT);

    PCVGuardian private immutable pcvGuardian =
        PCVGuardian(MainnetAddresses.PCV_GUARDIAN);

    Core private core = Core(MainnetAddresses.CORE);
    PegStabilityModule private daiPSM =
        PegStabilityModule(MainnetAddresses.VOLT_DAI_PSM);
    PegStabilityModule private usdcPSM =
        PegStabilityModule(MainnetAddresses.VOLT_USDC_PSM);

    IERC20 private dai = IERC20(MainnetAddresses.DAI);
    IVolt private fei = IVolt(MainnetAddresses.FEI);
    IERC20 private usdc = IERC20(MainnetAddresses.USDC);

    ERC20Allocator private allocator =
        ERC20Allocator(MainnetAddresses.ERC20ALLOCATOR);

    uint256 public constant scalingFactorUsdc = 1e12;
    int8 public constant decimalsNormalizerUsdc = 12;
    int8 public constant decimalsNormalizerDai = 0;

    uint248 public constant targetUsdcBalance = 100_000e6;
    uint248 public constant targetDaiBalance = 100_000e18;

    uint256 public constant maxRateLimitPerSecond = 1_000e18; /// 1k volt per second
    /// @notice rate limit per second is designed to allow system to replenish
    /// full buffercap every 24 hours assuming drip only
    /// 500,000 / 86,400 = 5.787 VOLT per second
    uint128 public constant rateLimitPerSecond = 5.78e18;
    uint128 public constant bufferCap = 300_000e18;

    function setUp() public {
        uint256 usdcBalance = usdc.balanceOf(
            MainnetAddresses.KRAKEN_USDC_WHALE
        );
        vm.prank(MainnetAddresses.KRAKEN_USDC_WHALE);
        usdc.transfer(address(usdcDeposit), usdcBalance);
        usdcDeposit.deposit();
    }

    function testSetup() public {
        assertEq(address(allocator.core()), address(core));
        assertEq(allocator.buffer(), bufferCap); /// buffercap has not been eaten into
        assertEq(allocator.rateLimitPerSecond(), rateLimitPerSecond);
        assertEq(allocator.MAX_RATE_LIMIT_PER_SECOND(), maxRateLimitPerSecond);

        {
            (
                address psmToken,
                uint248 psmTargetBalance,
                int8 decimalsNormalizer
            ) = allocator.allPSMs(address(daiPSM));
            address daipsm = allocator.pcvDepositToPSM(address(daiDeposit));

            assertEq(psmTargetBalance, targetDaiBalance);
            assertEq(decimalsNormalizer, decimalsNormalizerDai);
            assertEq(psmToken, address(dai));
            assertEq(daipsm, address(daiPSM));
        }

        {
            (
                address psmToken,
                uint248 psmTargetBalance,
                int8 decimalsNormalizer
            ) = allocator.allPSMs(address(usdcPSM));
            address usdcpsm = allocator.pcvDepositToPSM(address(usdcDeposit));

            assertEq(psmTargetBalance, targetUsdcBalance);
            assertEq(decimalsNormalizer, decimalsNormalizerUsdc);
            assertEq(psmToken, address(usdc));
            assertEq(usdcpsm, address(usdcPSM));
        }
    }

    /// ------ DRIP ------

    function testDripDai() public {
        uint256 daiBalance = dai.balanceOf(address(daiPSM));

        vm.prank(MainnetAddresses.GOVERNOR);
        daiPSM.withdraw(address(daiDeposit), daiBalance); /// send all dai to pcv deposit
        daiDeposit.deposit();

        (uint256 amountToDrip, uint256 adjustedAmountToDrip) = allocator
            .getDripDetails(address(daiPSM), daiDeposit);

        assertTrue(allocator.checkDripCondition(address(daiDeposit)));
        assertTrue(!allocator.checkSkimCondition(address(daiDeposit)));
        assertTrue(allocator.checkActionAllowed(address(daiDeposit)));
        allocator.drip(address(daiDeposit));
        assertTrue(!allocator.checkDripCondition(address(daiDeposit)));
        assertTrue(!allocator.checkSkimCondition(address(daiDeposit)));
        assertTrue(!allocator.checkActionAllowed(address(daiDeposit)));

        daiBalance = dai.balanceOf(address(daiPSM));

        assertEq(amountToDrip, adjustedAmountToDrip);
        assertEq(amountToDrip, targetDaiBalance);
        assertEq(daiBalance, targetDaiBalance);
        assertEq(allocator.buffer(), bufferCap - targetDaiBalance);
    }

    function testDripUsdc() public {
        uint256 usdcBalance = usdc.balanceOf(address(usdcPSM));

        vm.prank(MainnetAddresses.GOVERNOR);
        usdcPSM.withdraw(address(usdcDeposit), usdcBalance); /// send all dai to pcv deposit
        usdcDeposit.deposit(); /// deposit so it will be counted in balance

        (uint256 amountToDrip, uint256 adjustedAmountToDrip) = allocator
            .getDripDetails(address(usdcPSM), usdcDeposit);

        assertTrue(allocator.checkDripCondition(address(usdcDeposit)));
        assertTrue(allocator.checkActionAllowed(address(usdcDeposit)));
        allocator.drip(address(usdcDeposit));
        assertTrue(!allocator.checkDripCondition(address(usdcDeposit)));
        assertTrue(!allocator.checkActionAllowed(address(usdcDeposit)));

        usdcBalance = usdc.balanceOf(address(usdcPSM));
        assertEq(amountToDrip * scalingFactorUsdc, adjustedAmountToDrip);
        assertEq(amountToDrip, targetUsdcBalance);
        assertEq(usdcBalance, targetUsdcBalance);
        assertEq(
            allocator.buffer(),
            bufferCap - targetUsdcBalance * scalingFactorUsdc
        );
    }

    /// ------ SKIM ------

    function testSkimDai() public {
        uint256 daiBalance = daiDeposit.balance();
        uint256 daiPSMBalance = daiPSM.balance();

        vm.prank(MainnetAddresses.GOVERNOR);
        daiDeposit.withdraw(address(daiPSM), daiBalance); /// send all dai to psm

        (uint256 amountToSkim, uint256 adjustedAmountToSkim) = allocator
            .getSkimDetails(address(daiDeposit));

        uint256 skimAmount = daiPSM.balance() - targetDaiBalance;
        assertEq(amountToSkim, skimAmount);
        assertEq(adjustedAmountToSkim, skimAmount);

        assertTrue(!allocator.checkDripCondition(address(daiDeposit))); /// all assets are in dai psm, not eligble for skim
        assertTrue(allocator.checkSkimCondition(address(daiDeposit)));
        assertTrue(allocator.checkActionAllowed(address(daiDeposit)));

        allocator.skim(address(daiDeposit));

        assertTrue(!allocator.checkDripCondition(address(daiDeposit)));
        assertTrue(!allocator.checkSkimCondition(address(daiDeposit)));
        assertTrue(!allocator.checkActionAllowed(address(daiDeposit)));

        assertEq(dai.balanceOf(address(daiPSM)), targetDaiBalance);
        assertApproxEq(
            daiDeposit.balance().toInt256(),
            (daiBalance + daiPSMBalance - targetDaiBalance).toInt256(),
            0
        );

        /// buffer should be full as no depletion happened prior and skimming is regenerative
        assertEq(allocator.buffer(), bufferCap);
    }

    function testSkimUsdc() public {
        uint256 usdcBalance = usdcDeposit.balance();
        uint256 usdcPSMBalance = usdcPSM.balance();

        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.withdraw(address(usdcPSM), usdcBalance); /// send all usdc to psm

        (uint256 amountToSkim, uint256 adjustedAmountToSkim) = allocator
            .getSkimDetails(address(usdcDeposit));

        uint256 skimAmount = usdcPSM.balance() - targetUsdcBalance;
        assertEq(amountToSkim, skimAmount);
        assertEq(adjustedAmountToSkim, skimAmount * scalingFactorUsdc);

        assertTrue(!allocator.checkDripCondition(address(usdcDeposit))); /// all assets are in usdc psm, not eligble for skim
        assertTrue(allocator.checkSkimCondition(address(usdcDeposit)));
        assertTrue(allocator.checkActionAllowed(address(usdcDeposit)));

        allocator.skim(address(usdcDeposit));

        assertTrue(!allocator.checkDripCondition(address(usdcDeposit)));
        assertTrue(!allocator.checkSkimCondition(address(usdcDeposit)));
        assertTrue(!allocator.checkActionAllowed(address(usdcDeposit)));

        assertEq(usdc.balanceOf(address(usdcPSM)), targetUsdcBalance);
        assertApproxEq(
            usdcDeposit.balance().toInt256(),
            (usdcBalance + usdcPSMBalance - targetUsdcBalance).toInt256(),
            0
        );

        /// buffer should be full as no depletion happened prior and skimming is regenerative
        assertEq(allocator.buffer(), bufferCap);
    }

    /// ------ DRIP ------

    function testDripDaiViaDoAction() public {
        uint256 daiBalance = dai.balanceOf(address(daiPSM));

        vm.prank(MainnetAddresses.GOVERNOR);
        daiPSM.withdraw(address(daiDeposit), daiBalance); /// send all dai to pcv deposit
        daiDeposit.deposit();

        (uint256 amountToDrip, uint256 adjustedAmountToDrip) = allocator
            .getDripDetails(address(daiPSM), daiDeposit);

        assertTrue(allocator.checkDripCondition(address(daiDeposit)));
        assertTrue(!allocator.checkSkimCondition(address(daiDeposit)));
        assertTrue(allocator.checkActionAllowed(address(daiDeposit)));

        allocator.doAction(address(daiDeposit));

        assertTrue(!allocator.checkDripCondition(address(daiDeposit)));
        assertTrue(!allocator.checkSkimCondition(address(daiDeposit)));
        assertTrue(!allocator.checkActionAllowed(address(daiDeposit)));

        daiBalance = dai.balanceOf(address(daiPSM));

        assertEq(amountToDrip, adjustedAmountToDrip);
        assertEq(amountToDrip, targetDaiBalance);
        assertEq(daiBalance, targetDaiBalance);
        assertEq(allocator.buffer(), bufferCap - targetDaiBalance);
    }

    function testDripUsdcViaDoAction() public {
        uint256 usdcBalance = usdc.balanceOf(address(usdcPSM));

        vm.prank(MainnetAddresses.GOVERNOR);
        usdcPSM.withdraw(address(usdcDeposit), usdcBalance); /// send all dai to pcv deposit
        usdcDeposit.deposit(); /// deposit so it will be counted in balance

        (uint256 amountToDrip, uint256 adjustedAmountToDrip) = allocator
            .getDripDetails(address(usdcPSM), usdcDeposit);

        assertTrue(allocator.checkDripCondition(address(usdcDeposit)));
        assertTrue(allocator.checkActionAllowed(address(usdcDeposit)));

        allocator.doAction(address(usdcDeposit));

        assertTrue(!allocator.checkDripCondition(address(usdcDeposit)));
        assertTrue(!allocator.checkActionAllowed(address(usdcDeposit)));

        usdcBalance = usdc.balanceOf(address(usdcPSM));
        assertEq(amountToDrip * scalingFactorUsdc, adjustedAmountToDrip);
        assertEq(amountToDrip, targetUsdcBalance);
        assertEq(usdcBalance, targetUsdcBalance);
        assertEq(
            allocator.buffer(),
            bufferCap - targetUsdcBalance * scalingFactorUsdc
        );
    }

    /// ------ SKIM ------

    function testSkimDaiViaDoAction() public {
        uint256 daiBalance = daiDeposit.balance();
        uint256 daiPSMBalance = daiPSM.balance();

        vm.prank(MainnetAddresses.GOVERNOR);
        daiDeposit.withdraw(address(daiPSM), daiBalance); /// send all dai to psm

        (uint256 amountToSkim, uint256 adjustedAmountToSkim) = allocator
            .getSkimDetails(address(daiDeposit));

        uint256 skimAmount = daiPSM.balance() - targetDaiBalance;
        assertEq(amountToSkim, skimAmount);
        assertEq(adjustedAmountToSkim, skimAmount);

        assertTrue(!allocator.checkDripCondition(address(daiDeposit))); /// all assets are in dai psm, not eligble for skim
        assertTrue(allocator.checkSkimCondition(address(daiDeposit)));
        assertTrue(allocator.checkActionAllowed(address(daiDeposit)));

        allocator.doAction(address(daiDeposit));

        assertTrue(!allocator.checkDripCondition(address(daiDeposit)));
        assertTrue(!allocator.checkSkimCondition(address(daiDeposit)));
        assertTrue(!allocator.checkActionAllowed(address(daiDeposit)));

        assertEq(dai.balanceOf(address(daiPSM)), targetDaiBalance);
        assertApproxEq(
            daiDeposit.balance().toInt256(),
            (daiBalance + daiPSMBalance - targetDaiBalance).toInt256(),
            0
        );

        /// buffer should be full as no depletion happened prior and skimming is regenerative
        assertEq(allocator.buffer(), bufferCap);
    }

    function testSkimUsdcViaDoAction() public {
        uint256 usdcBalance = usdcDeposit.balance();
        uint256 usdcPSMBalance = usdcPSM.balance();

        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.withdraw(address(usdcPSM), usdcBalance); /// send all usdc to psm

        (uint256 amountToSkim, uint256 adjustedAmountToSkim) = allocator
            .getSkimDetails(address(usdcDeposit));

        uint256 skimAmount = usdcPSM.balance() - targetUsdcBalance;
        assertEq(amountToSkim, skimAmount);
        assertEq(adjustedAmountToSkim, skimAmount * scalingFactorUsdc);

        assertTrue(!allocator.checkDripCondition(address(usdcDeposit))); /// all assets are in usdc psm, not eligble for skim
        assertTrue(allocator.checkSkimCondition(address(usdcDeposit)));
        assertTrue(allocator.checkActionAllowed(address(usdcDeposit)));

        allocator.doAction(address(usdcDeposit));

        assertTrue(!allocator.checkDripCondition(address(usdcDeposit)));
        assertTrue(!allocator.checkSkimCondition(address(usdcDeposit)));
        assertTrue(!allocator.checkActionAllowed(address(usdcDeposit)));

        assertEq(usdc.balanceOf(address(usdcPSM)), targetUsdcBalance);
        assertApproxEq(
            usdcDeposit.balance().toInt256(),
            (usdcBalance + usdcPSMBalance - targetUsdcBalance).toInt256(),
            0
        );

        /// buffer should be full as no depletion happened prior and skimming is regenerative
        assertEq(allocator.buffer(), bufferCap);
    }
}
