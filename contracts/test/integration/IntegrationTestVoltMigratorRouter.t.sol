// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ICore} from "../../core/ICore.sol";
import {IVolt} from "../../volt/Volt.sol";
import {VoltSystemOracle} from "../../oracle/VoltSystemOracle.sol";
import {Vm} from "./../unit/utils/Vm.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {TimelockSimulation} from "./utils/TimelockSimulation.sol";
import {vip13} from "./vip/vip13.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {IPCVGuardian} from "../../pcv/IPCVGuardian.sol";
import {stdError} from "../unit/utils/StdLib.sol";
import {IGRLM, GlobalRateLimitedMinter} from "../../minter/GlobalRateLimitedMinter.sol";

contract IntegrationTestVoltMigratorRouterTest is TimelockSimulation, vip13 {
    using SafeCast for *;
    ICore core = ICore(MainnetAddresses.CORE);
    IERC20 private usdc = IERC20(MainnetAddresses.USDC);
    IERC20 private dai = IERC20(MainnetAddresses.DAI);
    uint224 public constant mintAmount = 100_000_000e18;

    VoltSystemOracle public oracle =
        VoltSystemOracle(MainnetAddresses.ORACLE_PASS_THROUGH);

    GlobalRateLimitedMinter public grlm;

    /// ---------- GRLM PARAMS ----------

    /// maximum rate limit per second is 100 VOLT
    uint256 public constant maxRateLimitPerSecondMinting = 100e18;

    /// replenish 500k VOLT per day
    uint128 public constant rateLimitPerSecondMinting = 5.787e18;

    uint128 public constant bufferCapMinting = uint128(mintAmount);

    function setUp() public {
        simulate(
            getMainnetProposal(),
            TimelockController(payable(MainnetAddresses.TIMELOCK_CONTROLLER)),
            IPCVGuardian(MainnetAddresses.PCV_GUARDIAN),
            MainnetAddresses.GOVERNOR,
            MainnetAddresses.EOA_1,
            vm,
            false
        );
        mainnetValidate();
        // Grant stablecoin balances to PSMs
        uint256 balance = usdc.balanceOf(MainnetAddresses.KRAKEN_USDC_WHALE);
        vm.prank(MainnetAddresses.KRAKEN_USDC_WHALE);
        usdc.transfer(address(voltV2UsdcPriceBoundPSM), balance);

        balance = dai.balanceOf(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        vm.prank(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        dai.transfer(address(voltV2DaiPriceBoundPSM), balance);

        vm.startPrank(MainnetAddresses.GOVERNOR);
        grlm = new GlobalRateLimitedMinter(
            address(coreV2),
            maxRateLimitPerSecondMinting,
            rateLimitPerSecondMinting,
            bufferCapMinting
        );

        coreV2.setGlobalRateLimitedMinter(IGRLM(address(grlm)));
        coreV2.grantMinter(address(grlm));
        coreV2.grantRateLimitedRedeemer(address(voltV2DaiPriceBoundPSM));
        coreV2.grantRateLimitedRedeemer(address(voltV2UsdcPriceBoundPSM));
        coreV2.grantRateLimitedMinter(address(voltV2DaiPriceBoundPSM));
        coreV2.grantRateLimitedMinter(address(voltV2UsdcPriceBoundPSM));
        coreV2.grantLocker(address(grlm));

        core.grantMinter(MainnetAddresses.GOVERNOR);
        coreV2.grantMinter(MainnetAddresses.GOVERNOR);
        oldVolt.mint(address(this), mintAmount);
        voltV2.mint(address(voltMigrator), mintAmount);
        vm.stopPrank();
    }

    function testRedeemUsdc(uint72 amountVoltIn) public {
        oldVolt.approve(address(migratorRouter), type(uint256).max);

        uint256 startBalance = usdc.balanceOf(address(this));
        uint256 minAmountOut = voltV2UsdcPriceBoundPSM.getRedeemAmountOut(
            amountVoltIn
        );

        uint256 currentPegPrice = oracle.getCurrentOraclePrice() / 1e12;
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

        uint256 startBalance = dai.balanceOf(address(this));
        uint256 minAmountOut = voltV2DaiPriceBoundPSM.getRedeemAmountOut(
            amountVoltIn
        );

        uint256 currentPegPrice = oracle.getCurrentOraclePrice();
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
        oldVolt.burn(mintAmount);

        uint256 minAmountOut = voltV2DaiPriceBoundPSM.getRedeemAmountOut(
            mintAmount
        );

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        migratorRouter.redeemDai(mintAmount, minAmountOut);
    }

    function testRedeemUsdcFailsUserNotEnoughVolt() public {
        oldVolt.approve(address(migratorRouter), type(uint256).max);
        oldVolt.burn(mintAmount);

        uint256 minAmountOut = voltV2DaiPriceBoundPSM.getRedeemAmountOut(
            mintAmount
        );

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        migratorRouter.redeemUSDC(mintAmount, minAmountOut);
    }

    function testRedeemDaiFailUnderfundedPSM() public {
        oldVolt.approve(address(migratorRouter), type(uint256).max);

        uint256 balance = dai.balanceOf(address(voltV2DaiPriceBoundPSM));
        vm.prank(address(voltV2DaiPriceBoundPSM));
        dai.transfer(address(0), balance);

        uint256 minAmountOut = voltV2DaiPriceBoundPSM.getRedeemAmountOut(
            mintAmount
        );

        vm.expectRevert("Dai/insufficient-balance");
        migratorRouter.redeemDai(mintAmount, minAmountOut);
    }

    function testRedeemUsdcFailUnderfundedPSM() public {
        oldVolt.approve(address(migratorRouter), type(uint256).max);

        uint256 balance = usdc.balanceOf(address(voltV2UsdcPriceBoundPSM));
        vm.prank(address(voltV2UsdcPriceBoundPSM));
        usdc.transfer(address(1), balance);

        uint256 minAmountOut = voltV2UsdcPriceBoundPSM.getRedeemAmountOut(
            mintAmount
        );

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        migratorRouter.redeemUSDC(mintAmount, minAmountOut);
    }

    function testRedeemDaiFailNoUserApproval() public {
        uint256 minAmountOut = voltV2DaiPriceBoundPSM.getRedeemAmountOut(
            mintAmount
        );

        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        migratorRouter.redeemDai(mintAmount, minAmountOut);
    }

    function testRedeemUsdcFailNoUserApproval() public {
        uint256 minAmountOut = voltV2DaiPriceBoundPSM.getRedeemAmountOut(
            mintAmount
        );

        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        migratorRouter.redeemUSDC(mintAmount, minAmountOut);
    }

    function testRedeemDaiFailUnderfundedMigrator() public {
        oldVolt.approve(address(migratorRouter), type(uint256).max);

        vm.prank(address(voltMigrator));
        voltV2.burn(mintAmount);

        uint256 minAmountOut = voltV2UsdcPriceBoundPSM.getRedeemAmountOut(
            mintAmount
        );

        vm.expectRevert(stdError.arithmeticError);
        migratorRouter.redeemDai(mintAmount, minAmountOut);
    }

    function testRedeemUsdcFailUnderfundedMigrator() public {
        oldVolt.approve(address(migratorRouter), type(uint256).max);

        vm.prank(address(voltMigrator));
        voltV2.burn(mintAmount);

        uint256 minAmountOut = voltV2UsdcPriceBoundPSM.getRedeemAmountOut(
            mintAmount
        );

        vm.expectRevert(stdError.arithmeticError);
        migratorRouter.redeemUSDC(mintAmount, minAmountOut);
    }
}
