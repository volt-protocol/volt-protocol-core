// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {PostProposalCheck} from "@test/integration/post-proposal-checks/PostProposalCheck.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {VoltV2} from "@voltprotocol/volt/VoltV2.sol";
import {CoreV2} from "@voltprotocol/core/CoreV2.sol";
import {PCVOracle} from "@voltprotocol/oracle/PCVOracle.sol";
import {PCVDeposit} from "@voltprotocol/pcv/PCVDeposit.sol";
import {SystemEntry} from "@voltprotocol/entry/SystemEntry.sol";
import {NonCustodialPSM} from "@voltprotocol/peg/NonCustodialPSM.sol";
import {GlobalRateLimitedMinter} from "@voltprotocol/rate-limits/GlobalRateLimitedMinter.sol";

contract IntegrationTestRateLimiters is PostProposalCheck {
    using SafeCast for *;

    address public constant user = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    uint256 public snapshotAfterMints;

    IERC20 private dai;
    IERC20 private usdc;
    CoreV2 private core;
    VoltV2 private volt;
    PCVOracle private pcvOracle;
    SystemEntry private systemEntry;
    NonCustodialPSM private daincpsm;
    NonCustodialPSM private usdcncpsm;
    GlobalRateLimitedMinter private grlm;
    address private morphoDaiPCVDeposit;
    address private morphoUsdcPCVDeposit;

    function setUp() public override {
        super.setUp();

        core = CoreV2(addresses.mainnet("CORE"));
        volt = VoltV2(addresses.mainnet("VOLT"));
        systemEntry = SystemEntry(addresses.mainnet("SYSTEM_ENTRY"));
        daincpsm = NonCustodialPSM(addresses.mainnet("PSM_NONCUSTODIAL_DAI"));
        usdcncpsm = NonCustodialPSM(addresses.mainnet("PSM_NONCUSTODIAL_USDC"));
        dai = IERC20(addresses.mainnet("DAI"));
        usdc = IERC20(addresses.mainnet("USDC"));
        grlm = GlobalRateLimitedMinter(
            addresses.mainnet("GLOBAL_RATE_LIMITED_MINTER")
        );
        pcvOracle = PCVOracle(addresses.mainnet("PCV_ORACLE"));
        morphoUsdcPCVDeposit = addresses.mainnet(
            "PCV_DEPOSIT_MORPHO_COMPOUND_USDC"
        );
        morphoDaiPCVDeposit = addresses.mainnet(
            "PCV_DEPOSIT_MORPHO_COMPOUND_DAI"
        );
    }

    /*
    Flow of the first user that mints VOLT in the new system.
    Performs checks on the global rate limits, and accounting
    in the new system's PCV Oracle.
    */
    function testUserPSMMint() public {
        {
            uint256 initialBuffer = grlm.buffer();

            // number of moved funds for tests
            uint256 amount = initialBuffer / 2;

            // user performs the first mint with DAI
            vm.startPrank(user);
            dai.approve(address(daincpsm), amount);
            daincpsm.mint(user, amount, 0);
            vm.stopPrank();

            // buffer has been used
            uint256 voltReceived1 = volt.balanceOf(user);
            assertEq(grlm.buffer(), initialBuffer - voltReceived1);

            // user performs the second mint wit USDC
            vm.startPrank(user);
            usdc.approve(address(usdcncpsm), amount / 1e12);
            usdcncpsm.mint(user, amount / 1e12, 0);
            vm.stopPrank();
            uint256 voltReceived2 = volt.balanceOf(user) - voltReceived1;

            // buffer has been used
            assertEq(
                grlm.buffer(),
                initialBuffer - voltReceived1 - voltReceived2
            );
        }

        snapshotAfterMints = vm.snapshot();

        vm.prank(address(core));
        grlm.setRateLimitPerSecond(5.787e18);

        // buffer replenishes over time
        vm.warp(block.timestamp + 3 days);

        // above limit rate reverts
        uint256 largeAmount = grlm.bufferCap() * 2;
        vm.startPrank(user);
        dai.approve(address(daincpsm), largeAmount);
        vm.expectRevert("RateLimited: buffer cap underflow");
        daincpsm.mint(user, largeAmount, 0);
        vm.stopPrank();
    }

    function testRedeemsDaiPsm(uint88 voltAmount) public {
        vm.assume(voltAmount >= 1e18);

        testUserPSMMint();

        vm.revertTo(snapshotAfterMints);
        vm.assume(voltAmount <= volt.balanceOf(user));

        uint256 daiAmountOut = daincpsm.getRedeemAmountOut(voltAmount);
        deal(address(dai), morphoDaiPCVDeposit, daiAmountOut);
        systemEntry.deposit(morphoDaiPCVDeposit);

        vm.startPrank(user);

        uint256 startingBuffer = grlm.buffer();
        uint256 startingDaiBalance = dai.balanceOf(user);

        volt.approve(address(daincpsm), voltAmount);
        daincpsm.redeem(user, voltAmount, daiAmountOut);

        uint256 endingBuffer = grlm.buffer();
        uint256 endingDaiBalance = dai.balanceOf(user);

        assertEq(endingDaiBalance - startingDaiBalance, daiAmountOut);
        assertEq(endingBuffer - startingBuffer, voltAmount);

        vm.stopPrank();
    }

    function testRedeemsDaiNcPsm(uint80 voltRedeemAmount) public {
        vm.assume(voltRedeemAmount >= 1e18);
        vm.assume(voltRedeemAmount <= 400_000e18);
        testUserPSMMint();

        vm.revertTo(snapshotAfterMints);

        uint256 daiAmountOut = daincpsm.getRedeemAmountOut(voltRedeemAmount);
        deal(address(dai), morphoDaiPCVDeposit, daiAmountOut * 2);
        systemEntry.deposit(morphoDaiPCVDeposit);

        uint256 startingBuffer = grlm.buffer();
        uint256 startingDaiBalance = dai.balanceOf(user);

        vm.startPrank(user);
        volt.approve(address(daincpsm), voltRedeemAmount);
        daincpsm.redeem(user, voltRedeemAmount, daiAmountOut);
        vm.stopPrank();

        uint256 endingBuffer = grlm.buffer();
        uint256 endingDaiBalance = dai.balanceOf(user);

        assertEq(endingBuffer - startingBuffer, voltRedeemAmount); /// grlm buffer replenished
        assertEq(endingDaiBalance - startingDaiBalance, daiAmountOut);
    }

    function testRedeemsUsdcNcPsm(uint80 voltRedeemAmount) public {
        vm.assume(voltRedeemAmount >= 1e18);
        vm.assume(voltRedeemAmount <= 400_000e18);
        testUserPSMMint();

        vm.revertTo(snapshotAfterMints);

        uint256 usdcAmountOut = usdcncpsm.getRedeemAmountOut(voltRedeemAmount);
        deal(address(usdc), morphoUsdcPCVDeposit, usdcAmountOut * 2);
        systemEntry.deposit(morphoUsdcPCVDeposit);

        vm.startPrank(user);

        uint256 startingBuffer = grlm.buffer();
        uint256 startingUsdcBalance = usdc.balanceOf(user);

        volt.approve(address(usdcncpsm), voltRedeemAmount);
        usdcncpsm.redeem(user, voltRedeemAmount, usdcAmountOut);

        uint256 endingBuffer = grlm.buffer();
        uint256 endingUsdcBalance = usdc.balanceOf(user);

        assertEq(endingBuffer - startingBuffer, voltRedeemAmount); /// buffer replenished
        assertEq(endingUsdcBalance - startingUsdcBalance, usdcAmountOut);

        vm.stopPrank();
    }

    function testRedeemsUsdcPsm(uint80 voltRedeemAmount) public {
        vm.assume(voltRedeemAmount >= 1e18);
        vm.assume(voltRedeemAmount <= 475_000e18);
        testUserPSMMint();

        vm.revertTo(snapshotAfterMints);

        uint256 usdcAmountOut = usdcncpsm.getRedeemAmountOut(voltRedeemAmount);
        deal(address(usdc), morphoUsdcPCVDeposit, usdcAmountOut);
        systemEntry.deposit(morphoUsdcPCVDeposit);

        uint256 startingBuffer = grlm.buffer();
        uint256 startingUsdcBalance = usdc.balanceOf(user);

        vm.startPrank(user);
        volt.approve(address(usdcncpsm), voltRedeemAmount);
        usdcncpsm.redeem(user, voltRedeemAmount, usdcAmountOut);
        vm.stopPrank();
    }
}
