// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ICore} from "../../core/ICore.sol";
import {OraclePassThrough} from "../../oracle/OraclePassThrough.sol";
import {IVolt} from "../../volt/Volt.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {vip13} from "./vip/vip13.sol";
import {TimelockSimulation} from "./utils/TimelockSimulation.sol";
import {PriceBoundPSM} from "../../peg/PriceBoundPSM.sol";
import {IPCVGuardian} from "../../pcv/IPCVGuardian.sol";

contract IntegrationTestVIP13 is TimelockSimulation, vip13 {
    using SafeCast for *;
    uint256 public constant mintAmountDai = 1_000_000e18;
    uint256 public constant mintAmountUsdc = 1_000_000e6;
    uint224 public constant voltMintAmount = 1_000_000e18;

    IERC20 public dai = IERC20(MainnetAddresses.DAI);
    IERC20 public usdc = IERC20(MainnetAddresses.USDC);
    ICore private core = ICore(MainnetAddresses.CORE);

    OraclePassThrough public oracle =
        OraclePassThrough(MainnetAddresses.ORACLE_PASS_THROUGH);

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

        vm.startPrank(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        dai.transfer(address(this), mintAmountDai);
        dai.transfer(address(voltV2DaiPriceBoundPSM), mintAmountDai * 2);
        vm.stopPrank();

        uint256 balance = usdc.balanceOf(MainnetAddresses.KRAKEN_USDC_WHALE);
        vm.prank(MainnetAddresses.KRAKEN_USDC_WHALE);
        usdc.transfer(address(this), balance);

        vm.startPrank(MainnetAddresses.GOVERNOR);
        core.grantMinter(MainnetAddresses.GOVERNOR);
        voltV2.mint(address(voltV2UsdcPriceBoundPSM), voltMintAmount);
        oldVolt.mint(address(this), voltMintAmount);
        voltV2.mint(address(this), voltMintAmount);
        vm.stopPrank();

        usdc.transfer(address(voltV2UsdcPriceBoundPSM), balance / 2);
    }

    function testSwapDaiForVolt() public {
        uint256 currentPegPrice = oracle.getCurrentOraclePrice();
        uint256 userStartingVoltBalance = voltV2.balanceOf(address(this));
        uint256 minAmountOut = voltV2DaiPriceBoundPSM.getMintAmountOut(
            mintAmountDai
        );
        uint256 startingPSMUnderlyingBalance = dai.balanceOf(
            address(voltV2DaiPriceBoundPSM)
        );

        dai.approve(address(voltV2DaiPriceBoundPSM), mintAmountDai);
        uint256 amountVoltOut = voltV2DaiPriceBoundPSM.mint(
            address(this),
            voltMintAmount,
            minAmountOut
        );

        uint256 endingUserVOLTBalance = voltV2.balanceOf(address(this));
        uint256 endingPSMUnderlyingBalance = dai.balanceOf(
            address(voltV2DaiPriceBoundPSM)
        );

        assertEq(
            endingUserVOLTBalance,
            amountVoltOut + userStartingVoltBalance
        );
        assertEq(
            endingPSMUnderlyingBalance - startingPSMUnderlyingBalance,
            mintAmountDai
        );
        assertApproxEq(
            ((mintAmountDai * 1e18) / currentPegPrice).toInt256(),
            minAmountOut.toInt256(),
            0
        );
    }

    function testSwapVoltForDai() public {
        uint256 currentPegPrice = oracle.getCurrentOraclePrice();
        uint256 startingUserUnderlyingBalance = dai.balanceOf(address(this));
        uint256 startingPSMUnderlyingBalance = dai.balanceOf(
            address(voltV2DaiPriceBoundPSM)
        );

        uint256 redeemAmountOut = voltV2DaiPriceBoundPSM.getRedeemAmountOut(
            voltMintAmount
        );
        uint256 startingUserVOLTBalance = voltV2.balanceOf(address(this));

        voltV2.approve(address(voltV2DaiPriceBoundPSM), voltMintAmount);
        uint256 amountOut = voltV2DaiPriceBoundPSM.redeem(
            address(this),
            voltMintAmount,
            redeemAmountOut
        );

        uint256 endingUserVOLTBalance = voltV2.balanceOf(address(this));
        uint256 endingUserUnderlyingBalance = dai.balanceOf(address(this));
        uint256 endingPSMUnderlyingBalance = dai.balanceOf(
            address(voltV2DaiPriceBoundPSM)
        );

        assertEq(
            startingUserVOLTBalance,
            endingUserVOLTBalance + mintAmountDai
        );
        assertEq(
            endingUserUnderlyingBalance,
            startingUserUnderlyingBalance + amountOut
        );
        assertEq(
            endingPSMUnderlyingBalance,
            startingPSMUnderlyingBalance - amountOut
        );
        assertApproxEq(
            ((voltMintAmount * currentPegPrice) / 1e18).toInt256(),
            amountOut.toInt256(),
            0
        );
    }

    function testSwapVoltForUsdc() public {
        uint256 currentPegPrice = oracle.getCurrentOraclePrice() / 1e12;
        uint256 startingUserUnderlyingBalance = usdc.balanceOf(address(this));
        uint256 startingPSMUnderlyingBalance = usdc.balanceOf(
            address(voltV2UsdcPriceBoundPSM)
        );
        uint256 redeemAmountOut = voltV2UsdcPriceBoundPSM.getRedeemAmountOut(
            voltMintAmount
        );
        uint256 startingUserVOLTBalance = voltV2.balanceOf(address(this));

        voltV2.approve(address(voltV2UsdcPriceBoundPSM), voltMintAmount);
        uint256 amountOut = voltV2UsdcPriceBoundPSM.redeem(
            address(this),
            voltMintAmount,
            redeemAmountOut
        );

        uint256 endingUserVOLTBalance = voltV2.balanceOf(address(this));
        uint256 endingUserUnderlyingBalance = usdc.balanceOf(address(this));
        uint256 endingPSMUnderlyingBalance = usdc.balanceOf(
            address(voltV2UsdcPriceBoundPSM)
        );

        assertEq(
            startingUserVOLTBalance,
            endingUserVOLTBalance + voltMintAmount
        );
        assertEq(
            endingUserUnderlyingBalance,
            startingUserUnderlyingBalance + amountOut
        );
        assertEq(
            endingPSMUnderlyingBalance,
            startingPSMUnderlyingBalance - amountOut
        );
        assertApproxEq(
            ((voltMintAmount * currentPegPrice) / 1e18).toInt256(),
            amountOut.toInt256(),
            0
        );
    }

    function testSwapUsdcForVolt() public {
        uint256 currentPegPrice = oracle.getCurrentOraclePrice();
        uint256 userStartingVoltBalance = voltV2.balanceOf(address(this));
        uint256 minAmountOut = voltV2UsdcPriceBoundPSM.getMintAmountOut(
            mintAmountUsdc
        );
        uint256 startingPSMUnderlyingBalance = usdc.balanceOf(
            address(voltV2UsdcPriceBoundPSM)
        );

        usdc.approve(address(voltV2UsdcPriceBoundPSM), mintAmountUsdc);
        uint256 amountVoltOut = voltV2UsdcPriceBoundPSM.mint(
            address(this),
            mintAmountUsdc,
            minAmountOut
        );

        uint256 endingUserVOLTBalance = voltV2.balanceOf(address(this));
        uint256 endingPSMUnderlyingBalance = usdc.balanceOf(
            address(voltV2UsdcPriceBoundPSM)
        );

        assertEq(
            endingUserVOLTBalance,
            amountVoltOut + userStartingVoltBalance
        );
        assertEq(
            endingPSMUnderlyingBalance - startingPSMUnderlyingBalance,
            mintAmountUsdc
        );
        assertApproxEq(
            ((((mintAmountUsdc * 1e18) / currentPegPrice)) * 1e12).toInt256(),
            minAmountOut.toInt256(),
            0
        );
    }
}
