// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {Vm} from "./../unit/utils/Vm.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {CurveRouter, ICurveRouter, ICurvePool} from "../../peg/curve/CurveRouter.sol";
import {PegStabilityModule} from "../../peg/PegStabilityModule.sol";
import {IVolt} from "../../volt/Volt.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {ICore, Core} from "../../core/Core.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {OraclePassThrough} from "../../oracle/OraclePassThrough.sol";

import "hardhat/console.sol";

contract IntegrationTestCurveRouter is DSTest {
    using SafeCast for *;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    CurveRouter private curveRouter;

    IVolt private volt = IVolt(MainnetAddresses.VOLT);
    IVolt private usdc = IVolt(MainnetAddresses.USDC);
    IVolt private dai = IVolt(MainnetAddresses.DAI);

    ICore private core = ICore(MainnetAddresses.CORE);

    PegStabilityModule VOLT_USDC_PSM =
        PegStabilityModule(MainnetAddresses.VOLT_USDC_PSM);

    OraclePassThrough public oracle =
        OraclePassThrough(MainnetAddresses.ORACLE_PASS_THROUGH);

    uint256 voltMintAmount = 100_000_000e18;

    function setUp() public {
        curveRouter = new CurveRouter(volt);

        vm.startPrank(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        dai.transfer(
            address(this),
            dai.balanceOf(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL) / 2
        );
        vm.stopPrank();

        vm.startPrank(MainnetAddresses.GOVERNOR);
        core.grantMinter(MainnetAddresses.GOVERNOR);
        volt.mint(address(this), voltMintAmount);
        vm.stopPrank();
    }

    function testMint(uint256 amountDaiIn) public {
        vm.assume(volt.balanceOf(address(VOLT_USDC_PSM)) / 1e18 >= amountDaiIn);
        dai.approve(address(curveRouter), type(uint256).max);

        amountDaiIn = amountDaiIn * 1e18;
        uint256 startingVoltBalance = volt.balanceOf(address(this));

        (
            uint256 amountTokenBReceived,
            uint256 amountVoltOut,
            uint256 index_i,
            uint256 index_j
        ) = curveRouter.getMintAmountOut(
                amountDaiIn,
                VOLT_USDC_PSM,
                MainnetAddresses.DAI_USDC_USDT_CURVE_POOL,
                address(dai),
                address(usdc),
                3
            );

        curveRouter.mint(
            address(this),
            amountDaiIn,
            amountTokenBReceived,
            amountVoltOut,
            VOLT_USDC_PSM,
            MainnetAddresses.DAI_USDC_USDT_CURVE_POOL,
            address(dai),
            index_i,
            index_j
        );

        uint256 endingVoltBalance = volt.balanceOf(address(this));

        assertEq(amountVoltOut, endingVoltBalance - startingVoltBalance);
    }

    function testGetMintAmountOut(uint256 amountDaiIn) public {
        vm.assume(volt.balanceOf(address(VOLT_USDC_PSM)) >= amountDaiIn);

        (uint256 amountTokenBReceived, uint256 amountVoltOut, , ) = curveRouter
            .getMintAmountOut(
                amountDaiIn,
                VOLT_USDC_PSM,
                MainnetAddresses.DAI_USDC_USDT_CURVE_POOL,
                address(dai),
                address(usdc),
                3
            );

        assertEq(
            amountVoltOut,
            VOLT_USDC_PSM.getMintAmountOut(amountTokenBReceived)
        );
    }

    function testRedeem(uint256 amountVoltIn) public {
        uint256 currentPegPrice = oracle.getCurrentOraclePrice();
        vm.assume(
            ((usdc.balanceOf(address(VOLT_USDC_PSM)) * 1e12) /
                currentPegPrice) *
                1e18 >=
                amountVoltIn
        );

        vm.prank(MainnetAddresses.GOVERNOR);
        VOLT_USDC_PSM.unpauseRedeem();

        volt.approve(address(curveRouter), type(uint256).max);

        uint256 startingDaiBalance = dai.balanceOf(address(this));

        (
            uint256 amountTokenAReceived,
            uint256 amountTokenBReceived
        ) = curveRouter.getRedeemAmountOut(
                amountVoltIn,
                VOLT_USDC_PSM,
                MainnetAddresses.DAI_USDC_USDT_CURVE_POOL,
                address(usdc),
                address(dai),
                3
            );

        uint256 amountDaiOut = curveRouter.redeem(
            address(this),
            amountVoltIn,
            amountTokenAReceived,
            amountTokenBReceived,
            VOLT_USDC_PSM,
            MainnetAddresses.DAI_USDC_USDT_CURVE_POOL,
            address(usdc),
            address(dai),
            3
        );

        uint256 endingDaiBalance = dai.balanceOf(address(this));

        assertEq(amountDaiOut, endingDaiBalance - startingDaiBalance);
    }

    function testGetRedeemAmountOut(uint256 amountVoltIn) public {
        vm.assume(volt.balanceOf(address(VOLT_USDC_PSM)) >= amountVoltIn);

        (uint256 amountTokenAReceived, ) = curveRouter.getRedeemAmountOut(
            amountVoltIn,
            VOLT_USDC_PSM,
            MainnetAddresses.DAI_USDC_USDT_CURVE_POOL,
            address(usdc),
            address(dai),
            3
        );

        assertEq(
            amountTokenAReceived,
            VOLT_USDC_PSM.getRedeemAmountOut(amountVoltIn)
        );
    }
}
