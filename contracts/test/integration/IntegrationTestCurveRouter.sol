// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {Vm} from "./../unit/utils/Vm.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {CurveRouter, ICurveRouter, ICurvePool} from "../../peg/curve/CurveRouter.sol";
import {IPegStabilityModule} from "../../peg/IPegStabilityModule.sol";
import {IVolt} from "../../volt/Volt.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {ICore, Core} from "../../core/Core.sol";

import "hardhat/console.sol";

contract IntegrationTestCurveRouter is DSTest {
    Vm public constant vm = Vm(HEVM_ADDRESS);

    CurveRouter private curveRouter;

    IVolt private volt = IVolt(MainnetAddresses.VOLT);
    IVolt private usdc = IVolt(MainnetAddresses.USDC);
    IVolt private dai = IVolt(MainnetAddresses.DAI);

    ICore private core = ICore(MainnetAddresses.CORE);

    IPegStabilityModule VOLT_USDC_PSM =
        IPegStabilityModule(MainnetAddresses.VOLT_USDC_PSM);

    function setUp() public {
        curveRouter = new CurveRouter(volt);

        uint256 balance = dai.balanceOf(MainnetAddresses.FEI_DAI_PSM);
        vm.prank(MainnetAddresses.FEI_DAI_PSM);
        dai.transfer(address(this), balance);
    }

    function testMint(uint256 amountDaiIn) public {
        vm.assume(volt.balanceOf(address(VOLT_USDC_PSM)) / 1e18 >= amountDaiIn);
        dai.approve(address(curveRouter), type(uint256).max);

        amountDaiIn = amountDaiIn * 1e18;
        (uint256 amountTokenBReceived, , ) = curveRouter.calculateSwap(
            amountDaiIn,
            MainnetAddresses.DAI_USDC_USDT_CURVE_POOL,
            address(dai),
            address(usdc),
            3
        );

        uint256 amountVoltOut = VOLT_USDC_PSM.getMintAmountOut(
            amountTokenBReceived
        );

        curveRouter.mint(
            address(this),
            amountDaiIn,
            amountVoltOut,
            VOLT_USDC_PSM,
            MainnetAddresses.DAI_USDC_USDT_CURVE_POOL,
            address(dai),
            address(usdc),
            3
        );

        console.log(volt.balanceOf(address(this)));
        assertEq(amountVoltOut, volt.balanceOf(address(this)));
    }

    function testGetMintAmountOut(uint256 amountDaiIn) public {
        vm.assume(volt.balanceOf(address(VOLT_USDC_PSM)) >= amountDaiIn);

        (uint256 amountTokenBReceived, uint256 amountVoltOut) = curveRouter
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

    function testRedeem() public {}
}
