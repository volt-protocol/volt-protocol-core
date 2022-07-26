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

contract IntegrationTestCurveRouter is DSTest {
    using SafeCast for *;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    CurveRouter private curveRouter;

    IVolt private volt = IVolt(MainnetAddresses.VOLT);
    IVolt private usdc = IVolt(MainnetAddresses.USDC);
    IVolt private dai = IVolt(MainnetAddresses.DAI);
    IVolt private frax = IVolt(MainnetAddresses.FRAX);

    ICore private core = ICore(MainnetAddresses.CORE);

    PegStabilityModule VOLT_USDC_PSM =
        PegStabilityModule(MainnetAddresses.VOLT_USDC_PSM);

    OraclePassThrough public oracle =
        OraclePassThrough(MainnetAddresses.ORACLE_PASS_THROUGH);

    uint256 voltMintAmount = 100_000_000e18;

    function setUp() public {
        ICurveRouter.TokenApproval[9] memory tokenApprovals = [
            ICurveRouter.TokenApproval({
                token: MainnetAddresses.DAI,
                contractToApprove: MainnetAddresses.DAI_USDC_USDT_CURVE_POOL
            }),
            ICurveRouter.TokenApproval({
                token: MainnetAddresses.USDT,
                contractToApprove: MainnetAddresses.DAI_USDC_USDT_CURVE_POOL
            }),
            ICurveRouter.TokenApproval({
                token: MainnetAddresses.USDC,
                contractToApprove: MainnetAddresses.DAI_USDC_USDT_CURVE_POOL
            }),
            ICurveRouter.TokenApproval({
                token: MainnetAddresses.FRAX,
                contractToApprove: MainnetAddresses.FRAX_3POOL
            }),
            ICurveRouter.TokenApproval({
                token: MainnetAddresses.USDC,
                contractToApprove: MainnetAddresses.FRAX_3POOL
            }),
            ICurveRouter.TokenApproval({
                token: MainnetAddresses.VOLT,
                contractToApprove: MainnetAddresses.VOLT_USDC_PSM
            }),
            ICurveRouter.TokenApproval({
                token: MainnetAddresses.USDC,
                contractToApprove: MainnetAddresses.VOLT_USDC_PSM
            }),
            ICurveRouter.TokenApproval({
                token: MainnetAddresses.VOLT,
                contractToApprove: MainnetAddresses.VOLT_FEI_PSM
            }),
            ICurveRouter.TokenApproval({
                token: MainnetAddresses.FEI,
                contractToApprove: MainnetAddresses.VOLT_FEI_PSM
            })
        ];

        curveRouter = new CurveRouter(volt, tokenApprovals);

        vm.startPrank(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        dai.transfer(
            address(this),
            dai.balanceOf(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL) / 2
        );
        vm.stopPrank();

        vm.startPrank(MainnetAddresses.FRAX_3POOL);
        frax.transfer(
            address(this),
            frax.balanceOf(MainnetAddresses.FRAX_3POOL) / 2
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
            uint256 amountTokenBReceived,
            uint256 index_i,
            uint256 index_j
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
            address(dai),
            index_i,
            index_j
        );

        uint256 endingDaiBalance = dai.balanceOf(address(this));

        assertEq(amountDaiOut, endingDaiBalance - startingDaiBalance);
    }

    function testGetRedeemAmountOut(uint256 amountVoltIn) public {
        vm.assume(volt.balanceOf(address(VOLT_USDC_PSM)) >= amountVoltIn);

        (uint256 amountTokenAReceived, , , ) = curveRouter.getRedeemAmountOut(
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

    function testMintMetaPool(uint256 amountFraxIn) public {
        // curve reverts when a value less than 3 is entered
        vm.assume(
            volt.balanceOf(address(VOLT_USDC_PSM)) >= amountFraxIn &&
                amountFraxIn > 2
        );

        frax.approve(address(curveRouter), type(uint256).max);

        uint256 startingVoltBalance = volt.balanceOf(address(this));

        (uint256 amountTokenBReceived, uint256 amountVoltOut) = curveRouter
            .getMintAmountOutMetaPool(
                amountFraxIn,
                VOLT_USDC_PSM,
                MainnetAddresses.FRAX_3POOL,
                0,
                2
            );

        curveRouter.mintMetaPool(
            address(this),
            amountFraxIn,
            amountTokenBReceived,
            amountVoltOut,
            VOLT_USDC_PSM,
            MainnetAddresses.FRAX_3POOL,
            MainnetAddresses.FRAX,
            0,
            2
        );

        uint256 endingVoltBalance = volt.balanceOf(address(this));

        assertEq(amountVoltOut, endingVoltBalance - startingVoltBalance);
    }

    function testGetMintAmountOutMetaPool(uint256 amountFraxIn) public {
        // curve reverts when a value less than 3 is entered
        vm.assume(
            volt.balanceOf(address(VOLT_USDC_PSM)) >= amountFraxIn &&
                amountFraxIn > 2
        );

        (uint256 amountTokenBReceived, uint256 amountVoltOut) = curveRouter
            .getMintAmountOutMetaPool(
                amountFraxIn,
                VOLT_USDC_PSM,
                MainnetAddresses.FRAX_3POOL,
                0,
                2
            );

        assertEq(
            amountVoltOut,
            VOLT_USDC_PSM.getMintAmountOut(amountTokenBReceived)
        );
    }

    function testGetRedeemAmountOutMetaPool(uint64 amountVoltIn) public {
        uint256 currentPegPrice = oracle.getCurrentOraclePrice();

        // bind value to be above 0 to prevent reversion from curve
        vm.assume(amountVoltIn / currentPegPrice > 0);

        (uint256 amountTokenAReceived, ) = curveRouter
            .getRedeemAmountOutMetaPool(
                amountVoltIn,
                VOLT_USDC_PSM,
                MainnetAddresses.FRAX_3POOL,
                2,
                0
            );

        assertEq(
            amountTokenAReceived,
            VOLT_USDC_PSM.getRedeemAmountOut(amountVoltIn)
        );
    }

    function testRedeemMetaPool(uint256 amountVoltIn) public {
        uint256 currentPegPrice = oracle.getCurrentOraclePrice();

        // bind value to be above 0 to prevent reversion from curve
        // make sure we don't deposit more than can be redeemed
        vm.assume(
            amountVoltIn / currentPegPrice > 0 &&
                amountVoltIn <
                ((usdc.balanceOf(address(VOLT_USDC_PSM)) * 1e12) /
                    currentPegPrice) *
                    1e18
        );

        volt.approve(address(curveRouter), type(uint256).max);
        vm.prank(MainnetAddresses.GOVERNOR);
        VOLT_USDC_PSM.unpauseRedeem();

        uint256 startingFraxBalance = frax.balanceOf(address(this));

        (
            uint256 amountTokenAReceived,
            uint256 amountTokenBReceived
        ) = curveRouter.getRedeemAmountOutMetaPool(
                amountVoltIn,
                VOLT_USDC_PSM,
                MainnetAddresses.FRAX_3POOL,
                2,
                0
            );

        uint256 amountOut = curveRouter.redeemMetaPool(
            address(this),
            amountVoltIn,
            amountTokenAReceived,
            amountTokenBReceived,
            VOLT_USDC_PSM,
            MainnetAddresses.FRAX_3POOL,
            MainnetAddresses.FRAX,
            2,
            0
        );

        uint256 endingFraxBalance = frax.balanceOf(address(this));

        assertEq(amountOut, endingFraxBalance - startingFraxBalance);
    }
}
