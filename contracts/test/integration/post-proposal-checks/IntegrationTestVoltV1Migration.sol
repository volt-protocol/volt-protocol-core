// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {PostProposalCheck} from "./PostProposalCheck.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {IVolt} from "../../../volt/IVolt.sol";
import {VoltV2} from "../../../volt/VoltV2.sol";
import {CoreV2} from "../../../core/CoreV2.sol";
import {stdError} from "@forge-std/StdError.sol";
import {MigratorRouter} from "../../../pcv/MigratorRouter.sol";
import {VoltSystemOracle} from "../../../oracle/VoltSystemOracle.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";
import {IVoltMigrator, VoltMigrator} from "../../../volt/VoltMigrator.sol";

contract IntegrationTestVoltV1Migration is PostProposalCheck {
    using SafeCast for *;

    uint224 public constant mintAmount = 100_000_000e18;

    TimelockController private timelockController;
    IVolt private oldVolt;
    VoltV2 private volt;
    VoltMigrator private voltMigrator;
    MigratorRouter private migratorRouter;
    PegStabilityModule private usdcpsm;
    PegStabilityModule private daipsm;
    IERC20 private dai;
    IERC20 private usdc;
    VoltSystemOracle private vso;
    address private grlm;
    address private multisig;
    address private coreV1;

    function setUp() public override {
        super.setUp();

        timelockController = TimelockController(
            payable(addresses.mainnet("TIMELOCK_CONTROLLER"))
        );
        oldVolt = IVolt(addresses.mainnet("V1_VOLT"));
        volt = VoltV2(addresses.mainnet("VOLT"));
        voltMigrator = VoltMigrator(addresses.mainnet("V1_MIGRATION_MIGRATOR"));
        migratorRouter = MigratorRouter(
            addresses.mainnet("V1_MIGRATION_ROUTER")
        );
        usdcpsm = PegStabilityModule(addresses.mainnet("PSM_USDC"));
        daipsm = PegStabilityModule(addresses.mainnet("PSM_DAI"));
        dai = IERC20(addresses.mainnet("DAI"));
        usdc = IERC20(addresses.mainnet("USDC"));
        vso = VoltSystemOracle(addresses.mainnet("VOLT_SYSTEM_ORACLE"));
        grlm = addresses.mainnet("GLOBAL_RATE_LIMITED_MINTER");
        multisig = addresses.mainnet("GOVERNOR");
        coreV1 = addresses.mainnet("V1_CORE");
    }

    function testExchangeTo(uint64 amountOldVoltToExchange) public {
        oldVolt.approve(address(voltMigrator), type(uint256).max);
        deal(address(oldVolt), address(this), amountOldVoltToExchange);
        deal(address(volt), address(voltMigrator), amountOldVoltToExchange);

        uint256 newVoltTotalSupply = volt.totalSupply();
        uint256 oldVoltTotalSupply = oldVolt.totalSupply();

        uint256 oldVoltBalanceBefore = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceBefore = volt.balanceOf(address(0xFFF));

        voltMigrator.exchangeTo(address(0xFFF), amountOldVoltToExchange);

        uint256 oldVoltBalanceAfter = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceAfter = volt.balanceOf(address(0xFFF));

        assertEq(
            newVoltBalanceAfter,
            newVoltBalanceBefore + amountOldVoltToExchange
        );
        assertEq(
            oldVoltBalanceAfter,
            oldVoltBalanceBefore - amountOldVoltToExchange
        );
        assertEq(
            oldVolt.totalSupply(),
            oldVoltTotalSupply - amountOldVoltToExchange
        );
        assertEq(volt.totalSupply(), newVoltTotalSupply); /// new volt supply remains unchanged
    }

    function testExchangeAllTo() public {
        uint256 amountOldVoltToExchange = 10_000e18;

        oldVolt.approve(address(voltMigrator), type(uint256).max);

        deal(address(oldVolt), address(this), amountOldVoltToExchange);
        deal(address(volt), address(voltMigrator), amountOldVoltToExchange);

        uint256 newVoltTotalSupply = volt.totalSupply();
        uint256 oldVoltTotalSupply = oldVolt.totalSupply();

        uint256 oldVoltBalanceBefore = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceBefore = volt.balanceOf(address(0xFFF));

        voltMigrator.exchangeAllTo(address(0xFFF));

        uint256 oldVoltBalanceAfter = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceAfter = volt.balanceOf(address(0xFFF));

        assertEq(
            newVoltBalanceAfter,
            newVoltBalanceBefore + oldVoltBalanceBefore
        );
        assertEq(oldVoltBalanceAfter, 0);
        assertEq(
            oldVolt.totalSupply(),
            oldVoltTotalSupply - oldVoltBalanceBefore
        );
        assertEq(volt.totalSupply(), newVoltTotalSupply);
    }

    function testExchangeFailsWhenApprovalNotGiven() public {
        vm.expectRevert("ERC20: burn amount exceeds allowance");
        voltMigrator.exchange(1e18);
    }

    function testExchangeToFailsWhenApprovalNotGiven() public {
        vm.expectRevert("ERC20: burn amount exceeds allowance");
        voltMigrator.exchangeTo(address(0xFFF), 1e18);
    }

    function testExchangeFailsMigratorUnderfunded() public {
        uint256 amountOldVoltToExchange = 100_000_000e18;

        vm.prank(grlm);
        volt.mint(address(voltMigrator), amountOldVoltToExchange);
        deal(address(oldVolt), address(this), amountOldVoltToExchange);

        oldVolt.approve(address(voltMigrator), type(uint256).max);

        vm.prank(address(voltMigrator));
        volt.burn(mintAmount);

        vm.expectRevert(stdError.arithmeticError);
        voltMigrator.exchange(amountOldVoltToExchange);
    }

    function testExchangeAllFailsMigratorUnderfunded() public {
        oldVolt.approve(address(voltMigrator), type(uint256).max);
        deal(address(oldVolt), address(this), mintAmount);

        vm.prank(grlm);
        volt.mint(address(voltMigrator), mintAmount);

        vm.prank(address(voltMigrator));
        volt.burn(mintAmount);

        vm.expectRevert(stdError.arithmeticError);
        voltMigrator.exchangeAll();
    }

    function testExchangeToFailsMigratorUnderfunded() public {
        deal(address(oldVolt), address(this), mintAmount);

        vm.prank(grlm);
        volt.mint(address(voltMigrator), mintAmount);

        uint256 amountOldVoltToExchange = 100_000_000e18;
        oldVolt.approve(address(voltMigrator), type(uint256).max);

        vm.prank(address(voltMigrator));
        volt.burn(mintAmount);

        vm.expectRevert(stdError.arithmeticError);
        voltMigrator.exchangeTo(address(0xFFF), amountOldVoltToExchange);
    }

    function testExchangeAllToFailsMigratorUnderfunded() public {
        vm.prank(grlm);
        volt.mint(address(voltMigrator), mintAmount);
        deal(address(oldVolt), address(this), mintAmount);

        oldVolt.approve(address(voltMigrator), type(uint256).max);

        vm.prank(address(voltMigrator));
        volt.burn(mintAmount);

        vm.expectRevert(stdError.arithmeticError);
        voltMigrator.exchangeAllTo(address(0xFFF));
    }

    function testExchangeAllWhenApprovalNotGiven() public {
        uint256 oldVoltBalanceBefore = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceBefore = volt.balanceOf(address(this));

        vm.expectRevert("VoltMigrator: no amount to exchange");
        voltMigrator.exchangeAll();

        uint256 oldVoltBalanceAfter = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceAfter = volt.balanceOf(address(this));

        assertEq(oldVoltBalanceBefore, oldVoltBalanceAfter);
        assertEq(newVoltBalanceBefore, newVoltBalanceAfter);
    }

    function testExchangeAllToWhenApprovalNotGiven() public {
        uint256 oldVoltBalanceBefore = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceBefore = volt.balanceOf(address(0xFFF));

        vm.expectRevert("VoltMigrator: no amount to exchange");
        voltMigrator.exchangeAllTo(address(0xFFF));

        uint256 oldVoltBalanceAfter = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceAfter = volt.balanceOf(address(0xFFF));

        assertEq(oldVoltBalanceBefore, oldVoltBalanceAfter);
        assertEq(newVoltBalanceBefore, newVoltBalanceAfter);
    }

    function testExchangeAllPartialApproval() public {
        deal(address(oldVolt), address(this), 100_000e18);

        uint256 amountOldVoltToExchange = oldVolt.balanceOf(address(this)) / 2; // exchange half of users balance

        oldVolt.approve(address(voltMigrator), amountOldVoltToExchange);

        vm.prank(grlm);
        volt.mint(address(voltMigrator), amountOldVoltToExchange);

        uint256 newVoltTotalSupply = volt.totalSupply();
        uint256 oldVoltTotalSupply = oldVolt.totalSupply();

        uint256 oldVoltBalanceBefore = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceBefore = volt.balanceOf(address(this));

        voltMigrator.exchangeAllTo(address(this));

        uint256 oldVoltBalanceAfter = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceAfter = volt.balanceOf(address(this));

        assertEq(
            newVoltBalanceAfter,
            newVoltBalanceBefore + amountOldVoltToExchange
        );
        assertEq(
            oldVoltBalanceAfter,
            oldVoltBalanceBefore - amountOldVoltToExchange
        );

        assertEq(
            oldVolt.totalSupply(),
            oldVoltTotalSupply - amountOldVoltToExchange
        );
        assertEq(volt.totalSupply(), newVoltTotalSupply);

        assertEq(oldVoltBalanceAfter, oldVoltBalanceBefore / 2);
    }

    function testExchangeAllToPartialApproval() public {
        uint256 amountOldVoltToExchange = mintAmount / 2; // exchange half of users balance
        oldVolt.approve(address(voltMigrator), amountOldVoltToExchange);

        vm.prank(grlm);
        volt.mint(address(voltMigrator), mintAmount);

        vm.prank(multisig);
        CoreV2(coreV1).grantMinter(address(this));
        oldVolt.mint(address(this), mintAmount);

        uint256 newVoltTotalSupply = volt.totalSupply();
        uint256 oldVoltTotalSupply = oldVolt.totalSupply();

        uint256 oldVoltBalanceBefore = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceBefore = volt.balanceOf(address(0xFFF));

        voltMigrator.exchangeAllTo(address(0xFFF));

        uint256 oldVoltBalanceAfter = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceAfter = volt.balanceOf(address(0xFFF));

        assertEq(
            newVoltBalanceAfter,
            newVoltBalanceBefore + amountOldVoltToExchange
        );
        assertEq(
            oldVoltBalanceAfter,
            oldVoltBalanceBefore - amountOldVoltToExchange
        );
        assertEq(
            oldVolt.totalSupply(),
            oldVoltTotalSupply - amountOldVoltToExchange
        );
        assertEq(volt.totalSupply(), newVoltTotalSupply);
        assertEq(oldVoltBalanceAfter, oldVoltBalanceBefore / 2);
    }

    function testSweep() public {
        uint256 amountToTransfer = 1_000_000e6;

        uint256 startingBalance = usdc.balanceOf(address(timelockController));

        deal(address(usdc), address(voltMigrator), amountToTransfer);

        vm.prank(multisig);
        voltMigrator.sweep(
            address(usdc),
            address(timelockController),
            amountToTransfer
        );

        uint256 endingBalance = usdc.balanceOf(address(timelockController));

        assertEq(endingBalance - startingBalance, amountToTransfer);
    }

    function testSweepNonGovernorFails() public {
        uint256 amountToTransfer = 1_000_000e6;

        deal(address(usdc), address(voltMigrator), amountToTransfer);

        vm.expectRevert("CoreRef: Caller is not a governor");
        voltMigrator.sweep(
            address(usdc),
            address(timelockController),
            amountToTransfer
        );
    }

    function testSweepNewVoltFails() public {
        uint256 amountToSweep = volt.balanceOf(address(voltMigrator));

        vm.prank(multisig);
        vm.expectRevert("VoltMigrator: cannot sweep new Volt");
        voltMigrator.sweep(
            address(volt),
            address(timelockController),
            amountToSweep
        );
    }

    function testRedeemUsdc(uint72 amountVoltIn) public {
        oldVolt.approve(address(migratorRouter), type(uint256).max);

        vm.prank(grlm);
        volt.mint(address(voltMigrator), amountVoltIn);

        vm.prank(multisig);
        CoreV2(coreV1).grantMinter(address(this));
        oldVolt.mint(address(this), amountVoltIn);

        uint256 startBalance = usdc.balanceOf(address(this));
        uint256 minAmountOut = usdcpsm.getRedeemAmountOut(amountVoltIn);

        deal(address(usdc), address(usdcpsm), minAmountOut);

        uint256 currentPegPrice = vso.getCurrentOraclePrice() / 1e12;
        uint256 amountOut = (amountVoltIn * currentPegPrice) / 1e18;

        uint256 redeemedAmount = migratorRouter.redeemUSDC(
            amountVoltIn,
            minAmountOut
        );
        uint256 endBalance = usdc.balanceOf(address(this));

        assertApproxEq(minAmountOut.toInt256(), amountOut.toInt256(), 0);
        assertEq(minAmountOut, endBalance - startBalance);
        assertEq(redeemedAmount, minAmountOut);
    }

    function testRedeemDai(uint72 amountVoltIn) public {
        oldVolt.approve(address(migratorRouter), type(uint256).max);

        vm.prank(grlm);
        volt.mint(address(voltMigrator), amountVoltIn);

        vm.prank(multisig);
        CoreV2(coreV1).grantMinter(address(this));
        oldVolt.mint(address(this), amountVoltIn);

        uint256 startBalance = dai.balanceOf(address(this));
        uint256 minAmountOut = daipsm.getRedeemAmountOut(amountVoltIn);

        deal(address(dai), address(daipsm), minAmountOut);

        uint256 currentPegPrice = vso.getCurrentOraclePrice();
        uint256 amountOut = (amountVoltIn * currentPegPrice) / 1e18;

        uint256 redeemedAmount = migratorRouter.redeemDai(
            amountVoltIn,
            minAmountOut
        );
        uint256 endBalance = dai.balanceOf(address(this));

        assertApproxEq(minAmountOut.toInt256(), amountOut.toInt256(), 0);
        assertEq(minAmountOut, endBalance - startBalance);
        assertEq(redeemedAmount, minAmountOut);
    }

    function testRedeemDaiFailsUserNotEnoughVolt() public {
        oldVolt.approve(address(migratorRouter), type(uint256).max);

        uint256 minAmountOut = daipsm.getRedeemAmountOut(mintAmount);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        migratorRouter.redeemDai(mintAmount, minAmountOut);
    }

    function testRedeemUsdcFailsUserNotEnoughVolt() public {
        oldVolt.approve(address(migratorRouter), type(uint256).max);

        uint256 minAmountOut = daipsm.getRedeemAmountOut(mintAmount);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        migratorRouter.redeemUSDC(mintAmount, minAmountOut);
    }

    function testRedeemDaiFailUnderfundedPSM() public {
        oldVolt.approve(address(migratorRouter), type(uint256).max);

        vm.prank(grlm);
        volt.mint(address(voltMigrator), mintAmount);

        vm.prank(multisig);
        CoreV2(coreV1).grantMinter(address(this));
        oldVolt.mint(address(this), mintAmount);

        uint256 balance = dai.balanceOf(address(daipsm));
        vm.prank(address(daipsm));
        dai.transfer(address(0), balance);

        uint256 minAmountOut = daipsm.getRedeemAmountOut(mintAmount);

        vm.expectRevert("Dai/insufficient-balance");
        migratorRouter.redeemDai(mintAmount, minAmountOut);
    }

    function testRedeemUsdcFailUnderfundedPSM() public {
        oldVolt.approve(address(migratorRouter), type(uint256).max);

        vm.prank(grlm);
        volt.mint(address(voltMigrator), mintAmount);

        vm.prank(multisig);
        CoreV2(coreV1).grantMinter(address(this));
        oldVolt.mint(address(this), mintAmount);

        uint256 balance = usdc.balanceOf(address(usdcpsm));
        vm.prank(address(usdcpsm));
        usdc.transfer(address(1), balance);

        uint256 minAmountOut = usdcpsm.getRedeemAmountOut(mintAmount);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        migratorRouter.redeemUSDC(mintAmount, minAmountOut);
    }

    function testRedeemDaiFailNoUserApproval() public {
        vm.prank(multisig);
        CoreV2(coreV1).grantMinter(address(this));
        oldVolt.mint(address(this), mintAmount);

        vm.prank(grlm);
        volt.mint(address(voltMigrator), mintAmount);

        uint256 minAmountOut = daipsm.getRedeemAmountOut(mintAmount);

        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        migratorRouter.redeemDai(mintAmount, minAmountOut);
    }

    function testRedeemUsdcFailNoUserApproval() public {
        vm.prank(multisig);
        CoreV2(coreV1).grantMinter(address(this));
        oldVolt.mint(address(this), mintAmount);

        vm.prank(grlm);
        volt.mint(address(voltMigrator), mintAmount);

        uint256 minAmountOut = daipsm.getRedeemAmountOut(mintAmount);

        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        migratorRouter.redeemUSDC(mintAmount, minAmountOut);
    }

    function testRedeemDaiFailUnderfundedMigrator() public {
        oldVolt.approve(address(migratorRouter), type(uint256).max);

        vm.prank(multisig);
        CoreV2(coreV1).grantMinter(address(this));
        oldVolt.mint(address(this), mintAmount);

        uint256 minAmountOut = usdcpsm.getRedeemAmountOut(mintAmount);

        vm.expectRevert(stdError.arithmeticError);
        migratorRouter.redeemDai(mintAmount, minAmountOut);
    }

    function testRedeemUsdcFailUnderfundedMigrator() public {
        oldVolt.approve(address(migratorRouter), type(uint256).max);

        vm.prank(multisig);
        CoreV2(coreV1).grantMinter(address(this));
        oldVolt.mint(address(this), mintAmount);

        uint256 minAmountOut = usdcpsm.getRedeemAmountOut(mintAmount);

        vm.expectRevert(stdError.arithmeticError);
        migratorRouter.redeemUSDC(mintAmount, minAmountOut);
    }
}
