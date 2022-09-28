// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ICore} from "../../core/ICore.sol";
import {IVolt, Volt} from "../../volt/Volt.sol";
import {VoltMigrator} from "../../volt/VoltMigrator.sol";
import {OraclePassThrough} from "../../oracle/OraclePassThrough.sol";
import {MigratorRouter} from "../../pcv/MigratorRouter.sol";
import {VoltV2} from "../../volt/VoltV2.sol";
import {Vm} from "./../unit/utils/Vm.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {TimelockSimulation} from "./utils/TimelockSimulation.sol";
import {vip13} from "./vip/vip13.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {PriceBoundPSM, PegStabilityModule} from "../../peg/PriceBoundPSM.sol";
import {IPegStabilityModule} from "../../peg/IPegStabilityModule.sol";
import {ERC20CompoundPCVDeposit} from "../../pcv/compound/ERC20CompoundPCVDeposit.sol";
import {TempCoreRef} from "../../refs/TempCoreRef.sol";
import {IPCVGuardian} from "../../pcv/IPCVGuardian.sol";

import "hardhat/console.sol";

contract IntegrationTestVoltMigratorRouterTest is TimelockSimulation, vip13 {
    uint256 public constant mintAmount = 100_000_000e18;

    IVolt oldVolt = IVolt(MainnetAddresses.VOLT);
    ICore core = ICore(MainnetAddresses.CORE);
    IERC20 private usdc = IERC20(MainnetAddresses.USDC);
    IERC20 private dai = IERC20(MainnetAddresses.DAI);

    uint256 reservesThreshold = type(uint256).max; /// max uint so that surplus can never be allocated into the pcv deposit

    function setUp() public {
        mainnetSetup();
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

        // Grant old volt balance to user, and new volt balance to migrator
        vm.startPrank(MainnetAddresses.GOVERNOR);
        core.grantMinter(MainnetAddresses.GOVERNOR);
        // mint old volt to user
        oldVolt.mint(address(this), mintAmount);
        // mint new volt to migrator contract
        voltV2.mint(address(voltMigrator), mintAmount);
        vm.stopPrank();

        // approve migratorRouter to use users old volt
        oldVolt.approve(address(migratorRouter), type(uint256).max);
    }

    function testRedeemUsdc(uint64 amountVoltIn) public {
        uint256 startBalance = usdc.balanceOf(address(this));
        uint256 minAmountOut = voltV2UsdcPriceBoundPSM.getRedeemAmountOut(
            amountVoltIn
        );
        migratorRouter.redeemUSDC(amountVoltIn, minAmountOut);
        uint256 endBalance = usdc.balanceOf(address(this));

        assertEq(minAmountOut, endBalance - startBalance);
    }

    function testRedeemDai(uint64 amountVoltIn) public {
        uint256 startBalance = dai.balanceOf(address(this));
        uint256 minAmountOut = voltV2DaiPriceBoundPSM.getRedeemAmountOut(
            amountVoltIn
        );
        migratorRouter.redeemDai(amountVoltIn, minAmountOut);
        uint256 endBalance = dai.balanceOf(address(this));

        assertEq(minAmountOut, endBalance - startBalance);
    }
}
