// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ICore} from "../../core/ICore.sol";
import {IVolt} from "../../volt/Volt.sol";
import {OraclePassThrough} from "../../oracle/OraclePassThrough.sol";
import {Vm} from "./../unit/utils/Vm.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {TimelockSimulation} from "./utils/TimelockSimulation.sol";
import {vip13} from "./vip/vip13.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {IPCVGuardian} from "../../pcv/IPCVGuardian.sol";

contract IntegrationTestVoltMigratorRouterTest is TimelockSimulation, vip13 {
    using SafeCast for *;
    IVolt oldVolt = IVolt(MainnetAddresses.VOLT);
    ICore core = ICore(MainnetAddresses.CORE);
    IERC20 private usdc = IERC20(MainnetAddresses.USDC);
    IERC20 private dai = IERC20(MainnetAddresses.DAI);

    OraclePassThrough public oracle =
        OraclePassThrough(MainnetAddresses.ORACLE_PASS_THROUGH);

    uint256 public constant mintAmount = 100_000_000e18;

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

        uint256 currentPegPrice = oracle.getCurrentOraclePrice() / 1e12;
        uint256 amountOut = (amountVoltIn * currentPegPrice) / 1e18;

        migratorRouter.redeemUSDC(amountVoltIn, minAmountOut);
        uint256 endBalance = usdc.balanceOf(address(this));

        assertApproxEq(minAmountOut.toInt256(), amountOut.toInt256(), 0);
        assertEq(minAmountOut, endBalance - startBalance);
    }

    function testRedeemDai(uint64 amountVoltIn) public {
        uint256 startBalance = dai.balanceOf(address(this));
        uint256 minAmountOut = voltV2DaiPriceBoundPSM.getRedeemAmountOut(
            amountVoltIn
        );

        uint256 currentPegPrice = oracle.getCurrentOraclePrice();
        uint256 amountOut = (amountVoltIn * currentPegPrice) / 1e18;

        migratorRouter.redeemDai(amountVoltIn, minAmountOut);
        uint256 endBalance = dai.balanceOf(address(this));

        assertApproxEq(minAmountOut.toInt256(), amountOut.toInt256(), 0);
        assertEq(minAmountOut, endBalance - startBalance);
    }
}
