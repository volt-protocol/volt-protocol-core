// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {Vm} from "./../unit/utils/Vm.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {CurveRouter, ICurveRouter, ICurvePool} from "../../peg/curve/CurveRouter.sol";
import {IPegStabilityModule} from "../../peg/IPegStabilityModule.sol";
import {IVolt} from "../../volt/Volt.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import "hardhat/console.sol";

contract IntegrationTestCurveRouter is DSTest {
    Vm public constant vm = Vm(HEVM_ADDRESS);

    CurveRouter private curveRouter;

    IVolt private volt = IVolt(MainnetAddresses.VOLT);
    IVolt private usdc = IVolt(MainnetAddresses.USDC);
    IVolt private dai = IVolt(MainnetAddresses.DAI);

    IPegStabilityModule VOLT_USDC_PSM =
        IPegStabilityModule(MainnetAddresses.VOLT_USDC_PSM);

    function setUp() public {
        curveRouter = new CurveRouter(volt);

        vm.prank(MainnetAddresses.FEI_DAI_PSM);
        dai.transfer(address(this), 10_000_000);
    }

    function testMint() public {
        dai.approve(address(curveRouter), type(uint256).max);

        curveRouter.mint(
            address(this),
            300_000,
            VOLT_USDC_PSM,
            MainnetAddresses.DAI_USDC_USDT_CURVE_POOL,
            address(dai),
            address(usdc)
        );

        volt.balanceOf(address(this));
    }

    function testGetMintAmountOut() public view {
        (uint256 amountTokenBReceived, uint256 amountVoltOut) = curveRouter
            .getMintAmountOut(
                10_000e18,
                VOLT_USDC_PSM,
                MainnetAddresses.DAI_USDC_USDT_CURVE_POOL,
                address(dai),
                address(usdc)
            );
    }
}
