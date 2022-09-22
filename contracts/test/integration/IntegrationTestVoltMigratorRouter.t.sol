// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ICore} from "../../core/ICore.sol";
import {IVolt, Volt} from "../../volt/Volt.sol";
import {VoltMigrator} from "../../volt/VoltMigrator.sol";
import {OraclePassThrough} from "../../oracle/OraclePassThrough.sol";
import {MigratorRouter} from "../../pcv/MigratorRouter.sol";
import {VoltV2} from "../../volt/VoltV2.sol";
import {Vm} from "./../unit/utils/Vm.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {PriceBoundPSM, PegStabilityModule} from "../../peg/PriceBoundPSM.sol";
import {IPegStabilityModule} from "../../peg/IPegStabilityModule.sol";
import {ERC20CompoundPCVDeposit} from "../../pcv/compound/ERC20CompoundPCVDeposit.sol";
import {TempCoreRef} from "../../refs/TempCoreRef.sol";

import "hardhat/console.sol";

contract IntegrationTestVoltMigratorRouterTest is DSTest {
    PriceBoundPSM private usdcPSM;
    PriceBoundPSM private daiPSM;
    VoltMigrator private voltMigrator;
    MigratorRouter private migratorRouter;
    VoltV2 private newVolt;
    TempCoreRef private coreRef;

    /// @notice Oracle Pass Through contract
    OraclePassThrough private oracle =
        OraclePassThrough(MainnetAddresses.ORACLE_PASS_THROUGH);

    ERC20CompoundPCVDeposit private compoundUsdcPcvDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT);

    ERC20CompoundPCVDeposit private compoundDaiPcvDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_DAI_PCV_DEPOSIT);

    IVolt oldVolt = IVolt(MainnetAddresses.VOLT);
    ICore core = ICore(MainnetAddresses.CORE);
    IERC20 private usdc = IERC20(MainnetAddresses.USDC);
    IERC20 private dai = IERC20(MainnetAddresses.DAI);

    Vm public constant vm = Vm(HEVM_ADDRESS);

    uint256 public constant mintAmount = 100_000_000e18;

    /// these are inverted
    uint256 voltDaiFloorPrice = 9_000; /// 1 volt for .9 dai is the max allowable price
    uint256 voltDaiCeilingPrice = 10_000; /// 1 volt for 1 dai is the minimum price

    uint256 voltUsdcFloorPrice = 9_000e12; /// 1 volt for .9 usdc is the max allowable price
    uint256 voltUsdcCeilingPrice = 10_000e12; /// 1 volt for 1 usdc is the minimum price

    uint256 reservesThreshold = type(uint256).max; /// max uint so that surplus can never be allocated into the pcv deposit

    function setUp() public {
        // Deploy new volt token
        newVolt = new VoltV2(MainnetAddresses.CORE);

        // Deploy new PSMs
        PegStabilityModule.OracleParams memory oracleParamsUsdc;
        PegStabilityModule.OracleParams memory oracleParamsDai;

        oracleParamsUsdc = PegStabilityModule.OracleParams({
            coreAddress: address(core),
            oracleAddress: address(oracle),
            backupOracle: address(0),
            decimalsNormalizer: 12,
            doInvert: true,
            volt: IVolt(address(newVolt))
        });

        oracleParamsDai = PegStabilityModule.OracleParams({
            coreAddress: address(core),
            oracleAddress: address(oracle),
            backupOracle: address(0),
            decimalsNormalizer: 0,
            doInvert: true,
            volt: IVolt(address(newVolt))
        });

        usdcPSM = new PriceBoundPSM(
            voltUsdcFloorPrice,
            voltUsdcCeilingPrice,
            oracleParamsUsdc,
            0,
            0,
            reservesThreshold,
            10_000e18,
            10_000_000e18,
            IERC20(address(usdc)),
            compoundUsdcPcvDeposit
        );

        daiPSM = new PriceBoundPSM(
            voltDaiFloorPrice,
            voltDaiCeilingPrice,
            oracleParamsDai,
            0,
            0,
            reservesThreshold,
            10_000e18,
            10_000_000e18,
            IERC20(address(dai)),
            compoundUsdcPcvDeposit
        );

        // Deploy TempCoreRef
        coreRef = new TempCoreRef(
            MainnetAddresses.CORE,
            IVolt(address(newVolt))
        );

        // Deploy Volt Migrator
        voltMigrator = new VoltMigrator(
            MainnetAddresses.CORE,
            address(newVolt)
        );

        // Deploy Migrator Router
        migratorRouter = new MigratorRouter(
            address(newVolt),
            address(voltMigrator),
            daiPSM,
            usdcPSM
        );

        // Grant stablecoin balances to PSMs
        uint256 balance = usdc.balanceOf(MainnetAddresses.MAKER_USDC_PSM);
        vm.prank(MainnetAddresses.MAKER_USDC_PSM);
        usdc.transfer(address(usdcPSM), balance);

        balance = dai.balanceOf(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        vm.prank(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        dai.transfer(address(daiPSM), balance);

        // Grant old volt balance to user, and new volt balance to migrator
        vm.startPrank(MainnetAddresses.GOVERNOR);
        core.grantMinter(MainnetAddresses.GOVERNOR);
        // mint old volt to user
        oldVolt.mint(address(this), mintAmount);
        // mint new volt to migrator contract
        newVolt.mint(address(voltMigrator), mintAmount);
        vm.stopPrank();

        // approve migratorRouter to use users old volt
        oldVolt.approve(address(migratorRouter), type(uint256).max);
    }

    function testRedeemUsdc(uint64 amountVoltIn) public {
        uint256 minAmountOut = usdcPSM.getRedeemAmountOut(amountVoltIn);

        migratorRouter.redeemUSDC(amountVoltIn, minAmountOut);
    }

    function testRedeemDai(uint64 amountVoltIn) public {
        uint256 minAmountOut = daiPSM.getRedeemAmountOut(amountVoltIn);

        migratorRouter.redeemDai(amountVoltIn, minAmountOut);
    }
}
