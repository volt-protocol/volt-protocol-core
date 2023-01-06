// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {PostProposalCheck} from "./PostProposalCheck.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {VoltV2} from "../../../volt/VoltV2.sol";
import {CoreV2} from "../../../core/CoreV2.sol";
import {PCVOracle} from "../../../oracle/PCVOracle.sol";
import {SystemEntry} from "../../../entry/SystemEntry.sol";
import {ERC20Allocator} from "../../../pcv/utils/ERC20Allocator.sol";
import {NonCustodialPSM} from "../../../peg/NonCustodialPSM.sol";
import {GlobalRateLimitedMinter} from "../../../limiter/GlobalRateLimitedMinter.sol";
import {GlobalSystemExitRateLimiter} from "../../../limiter/GlobalSystemExitRateLimiter.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";

contract IntegrationTestRateLimiters is PostProposalCheck {
    using SafeCast for *;

    address public constant user = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    uint256 public snapshotAfterMints;

    CoreV2 private core;
    VoltV2 private volt;
    SystemEntry private systemEntry;
    ERC20Allocator private allocator;
    PegStabilityModule private usdcpsm;
    PegStabilityModule private daipsm;
    NonCustodialPSM private usdcncpsm;
    NonCustodialPSM private daincpsm;
    IERC20 private dai;
    IERC20 private usdc;
    GlobalRateLimitedMinter private grlm;
    GlobalSystemExitRateLimiter private gserl;
    PCVOracle private pcvOracle;
    address private morphoUsdcPCVDeposit;
    address private morphoDaiPCVDeposit;

    function setUp() public override {
        super.setUp();

        core = CoreV2(addresses.mainnet("CORE"));
        volt = VoltV2(addresses.mainnet("VOLT"));
        systemEntry = SystemEntry(addresses.mainnet("SYSTEM_ENTRY"));
        allocator = ERC20Allocator(addresses.mainnet("PSM_ALLOCATOR"));
        usdcpsm = PegStabilityModule(addresses.mainnet("PSM_USDC"));
        daipsm = PegStabilityModule(addresses.mainnet("PSM_DAI"));
        usdcncpsm = NonCustodialPSM(addresses.mainnet("PSM_NONCUSTODIAL_USDC"));
        daincpsm = NonCustodialPSM(addresses.mainnet("PSM_NONCUSTODIAL_DAI"));
        dai = IERC20(addresses.mainnet("DAI"));
        usdc = IERC20(addresses.mainnet("USDC"));
        grlm = GlobalRateLimitedMinter(
            addresses.mainnet("GLOBAL_RATE_LIMITED_MINTER")
        );
        gserl = GlobalSystemExitRateLimiter(
            addresses.mainnet("GLOBAL_SYSTEM_EXIT_RATE_LIMITER")
        );
        pcvOracle = PCVOracle(addresses.mainnet("PCV_ORACLE"));
        morphoUsdcPCVDeposit = addresses.mainnet("PCV_DEPOSIT_MORPHO_USDC");
        morphoDaiPCVDeposit = addresses.mainnet("PCV_DEPOSIT_MORPHO_DAI");
    }

    /*
    Flow of the first user that mints VOLT in the new system.
    Performs checks on the global rate limits, and accounting
    in the new system's PCV Oracle.
    */
    function testUserPSMMint() public {
        // read initial buffer left
        uint256 bufferCap = grlm.bufferCap();
        uint256 initialBuffer = grlm.buffer();

        // number of moved funds for tests
        uint256 amount = initialBuffer / 2;
        (, uint256 daiPSMTargetBalance, ) = allocator.allPSMs(address(daipsm));
        (, uint256 usdcPSMTargetBalance, ) = allocator.allPSMs(
            address(usdcpsm)
        );

        // read initial pcv
        (uint256 startLiquidPcv, , ) = pcvOracle.getTotalPcv();
        // read initial psm balances
        uint256 startPsmDaiBalance = dai.balanceOf(address(daipsm));
        uint256 startPsmUsdcBalance = usdc.balanceOf(address(usdcpsm));

        // user performs the first mint with DAI
        vm.startPrank(user);
        dai.approve(address(daipsm), amount);
        daipsm.mint(user, amount, 0);
        vm.stopPrank();

        // buffer has been used
        uint256 voltReceived1 = volt.balanceOf(user);
        assertEq(grlm.buffer(), initialBuffer - voltReceived1);

        allocator.skim(morphoDaiPCVDeposit);
        // after first mint, pcv increased by amount
        (uint256 liquidPcv2, , ) = pcvOracle.getTotalPcv();
        assertApproxEq(
            liquidPcv2.toInt256(),
            (startLiquidPcv + startPsmDaiBalance + amount - daiPSMTargetBalance)
                .toInt256(),
            0
        );

        // user performs the second mint wit USDC
        vm.startPrank(user);
        usdc.approve(address(usdcpsm), amount / 1e12);
        usdcpsm.mint(user, amount / 1e12, 0);
        vm.stopPrank();
        uint256 voltReceived2 = volt.balanceOf(user) - voltReceived1;

        // buffer has been used
        assertEq(grlm.buffer(), initialBuffer - voltReceived1 - voltReceived2);

        allocator.skim(morphoUsdcPCVDeposit);
        {
            // after second mint, pcv is = 2 * amount
            (uint256 liquidPcv3, , ) = pcvOracle.getTotalPcv();
            assertApproxEq(
                liquidPcv3.toInt256(),
                (liquidPcv2 +
                    startPsmUsdcBalance *
                    1e12 +
                    amount -
                    usdcPSMTargetBalance *
                    1e12).toInt256(),
                0
            );
        }
        snapshotAfterMints = vm.snapshot();

        vm.prank(address(core));
        grlm.setRateLimitPerSecond(5.787e18);

        // buffer replenishes over time
        vm.warp(block.timestamp + 3 days);

        // above limit rate reverts
        vm.startPrank(user);
        dai.approve(address(daipsm), bufferCap * 2);
        vm.expectRevert("RateLimited: rate limit hit");
        daipsm.mint(user, bufferCap * 2, 0);
        vm.stopPrank();
    }

    function testRedeemsDaiPsm(uint88 voltAmount) public {
        testUserPSMMint();

        vm.revertTo(snapshotAfterMints);
        vm.assume(voltAmount <= volt.balanceOf(user));

        {
            uint256 daiAmountOut = daipsm.getRedeemAmountOut(voltAmount);
            deal(address(dai), address(daipsm), daiAmountOut);

            vm.startPrank(user);

            uint256 startingBuffer = grlm.buffer();
            uint256 startingDaiBalance = dai.balanceOf(user);

            volt.approve(address(daipsm), voltAmount);
            daipsm.redeem(user, voltAmount, daiAmountOut);

            uint256 endingBuffer = grlm.buffer();
            uint256 endingDaiBalance = dai.balanceOf(user);

            assertEq(endingDaiBalance - startingDaiBalance, daiAmountOut);
            assertEq(endingBuffer - startingBuffer, voltAmount);

            vm.stopPrank();
        }
    }

    function testRedeemsDaiNcPsm(uint80 voltRedeemAmount) public {
        vm.assume(voltRedeemAmount >= 1e18);
        vm.assume(voltRedeemAmount <= 400_000e18);
        testUserPSMMint();

        vm.revertTo(snapshotAfterMints);

        {
            uint256 daiAmountOut = daincpsm.getRedeemAmountOut(
                voltRedeemAmount
            );
            deal(address(dai), morphoDaiPCVDeposit, daiAmountOut * 2);
            systemEntry.deposit(morphoDaiPCVDeposit);

            vm.startPrank(user);

            uint256 startingBuffer = grlm.buffer();
            uint256 startingExitBuffer = gserl.buffer();
            uint256 startingDaiBalance = dai.balanceOf(user);

            volt.approve(address(daincpsm), voltRedeemAmount);
            daincpsm.redeem(user, voltRedeemAmount, daiAmountOut);

            uint256 endingBuffer = grlm.buffer();
            uint256 endingExitBuffer = gserl.buffer();
            uint256 endingDaiBalance = dai.balanceOf(user);

            assertEq(endingBuffer - startingBuffer, voltRedeemAmount); /// grlm buffer replenished
            assertEq(endingDaiBalance - startingDaiBalance, daiAmountOut);
            assertEq(startingExitBuffer - endingExitBuffer, daiAmountOut); /// exit buffer depleted

            vm.stopPrank();
        }
    }

    function testRedeemsUsdcNcPsm(uint80 voltRedeemAmount) public {
        vm.assume(voltRedeemAmount >= 1e18);
        vm.assume(voltRedeemAmount <= 400_000e18);
        testUserPSMMint();

        vm.revertTo(snapshotAfterMints);

        {
            uint256 usdcAmountOut = usdcncpsm.getRedeemAmountOut(
                voltRedeemAmount
            );
            deal(address(usdc), morphoUsdcPCVDeposit, usdcAmountOut * 2);
            systemEntry.deposit(morphoUsdcPCVDeposit);

            vm.startPrank(user);

            uint256 startingBuffer = grlm.buffer();
            uint256 startingExitBuffer = gserl.buffer();
            uint256 startingUsdcBalance = usdc.balanceOf(user);

            volt.approve(address(usdcncpsm), voltRedeemAmount);
            usdcncpsm.redeem(user, voltRedeemAmount, usdcAmountOut);

            uint256 endingBuffer = grlm.buffer();
            uint256 endingExitBuffer = gserl.buffer();
            uint256 endingUsdcBalance = usdc.balanceOf(user);

            assertEq(endingBuffer - startingBuffer, voltRedeemAmount); /// buffer replenished
            assertEq(endingUsdcBalance - startingUsdcBalance, usdcAmountOut);
            assertEq(
                startingExitBuffer - endingExitBuffer,
                usdcAmountOut * 1e12
            ); /// ensure buffer adjusted up 12 decimals, buffer depleted

            vm.stopPrank();
        }
    }

    function testRedeemsUsdcPsm(uint80 voltRedeemAmount) public {
        vm.assume(voltRedeemAmount >= 1e18);
        vm.assume(voltRedeemAmount <= 475_000e18);
        testUserPSMMint();

        vm.revertTo(snapshotAfterMints);

        {
            uint256 usdcAmountOut = usdcpsm.getRedeemAmountOut(
                voltRedeemAmount
            );
            deal(address(usdc), address(usdcpsm), usdcAmountOut);

            vm.startPrank(user);

            uint256 startingBuffer = grlm.buffer();
            uint256 startingUsdcBalance = usdc.balanceOf(user);

            volt.approve(address(usdcpsm), voltRedeemAmount);
            usdcpsm.redeem(user, voltRedeemAmount, usdcAmountOut);

            uint256 endingBuffer = grlm.buffer();
            uint256 endingUsdcBalance = usdc.balanceOf(user);

            assertEq(endingBuffer - startingBuffer, voltRedeemAmount);
            assertEq(endingUsdcBalance - startingUsdcBalance, usdcAmountOut);

            vm.stopPrank();
        }
    }
}
