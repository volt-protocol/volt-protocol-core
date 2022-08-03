// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "./../unit/utils/Vm.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {getCore, getAddresses, VoltTestAddresses} from "./../unit/utils/Fixtures.sol";
import {Decimal} from "./../../external/Decimal.sol";
import {PriceBoundPSM} from "./../../peg/PriceBoundPSM.sol";
import {IScalingPriceOracle, ScalingPriceOracle} from "./../../oracle/ScalingPriceOracle.sol";
import {VoltSystemOracle} from "./../../oracle/VoltSystemOracle.sol";
import {OraclePassThrough} from "./../../oracle/OraclePassThrough.sol";
import {ArbitrumAddresses} from "./fixtures/ArbitrumAddresses.sol";
import {Constants} from "../../Constants.sol";
import {IVolt} from "../../volt/IVolt.sol";
import {TimelockSimulation} from "./utils/TimelockSimulation.sol";
import {vip2} from "./vip/vip2.sol";

contract ArbitrumTestVoltSystemOracle is TimelockSimulation, vip2 {
    using Decimal for Decimal.D256;
    using SafeCast for *;

    /// @notice reference to Volt
    IVolt private volt = IVolt(ArbitrumAddresses.VOLT);

    /// @notice reference to Dai
    IERC20 private dai = IERC20(ArbitrumAddresses.DAI);

    /// @notice reference to USDC
    IERC20 private usdc = IERC20(ArbitrumAddresses.USDC);

    /// @notice scaling price oracle on Arbitrum today
    ScalingPriceOracle private scalingPriceOracle =
        ScalingPriceOracle(ArbitrumAddresses.DEPRECATED_SCALING_PRICE_ORACLE);

    /// @notice existing Oracle Pass Through deployed on mainnet
    OraclePassThrough private immutable existingOraclePassThrough =
        OraclePassThrough(ArbitrumAddresses.DEPRECATED_ORACLE_PASS_THROUGH);

    /// @notice new Volt System Oracle
    VoltSystemOracle private voltSystemOracle =
        VoltSystemOracle(ArbitrumAddresses.VOLT_SYSTEM_ORACLE);

    /// @notice new Oracle Pass Through
    OraclePassThrough private oraclePassThrough =
        OraclePassThrough(ArbitrumAddresses.ORACLE_PASS_THROUGH);

    /// @notice increase price by x% per month
    uint256 public constant annualChangeRateBasisPoints = 200;

    /// @notice dai volt PSM
    PriceBoundPSM private immutable daiPSM =
        PriceBoundPSM(ArbitrumAddresses.VOLT_DAI_PSM);

    /// @notice usdc volt PSM
    PriceBoundPSM private immutable usdcPSM =
        PriceBoundPSM(ArbitrumAddresses.VOLT_USDC_PSM);

    /// @notice new Volt System Oracle start time
    uint256 constant startTime = 1659468611;

    function setUp() public {
        /// set mint fees to 5 bips
        vm.startPrank(ArbitrumAddresses.GOVERNOR);
        daiPSM.setMintFee(5);
        usdcPSM.setMintFee(5);
        vm.stopPrank();

        vm.warp(startTime);
    }

    function testSetup() public {
        assertEq(
            address(oraclePassThrough.scalingPriceOracle()),
            address(voltSystemOracle)
        );
        assertEq(
            address(existingOraclePassThrough.scalingPriceOracle()),
            address(scalingPriceOracle)
        );
    }

    function testPriceEquivalenceAtTermEnd() public {
        assertApproxEq(
            scalingPriceOracle.getCurrentOraclePrice().toInt256(),
            voltSystemOracle.getCurrentOraclePrice().toInt256(),
            allowedDeviationArbitrum
        );
        /// because start time is a little past when the calculated start time would be,
        /// there is a slight but non zero deviation (835 seconds of unnacrued interest)
        assertApproxEq(
            voltSystemOracle.oraclePrice().toInt256(),
            voltSystemOracle.getCurrentOraclePrice().toInt256(),
            0
        );
        assertApproxEq(
            oraclePassThrough.getCurrentOraclePrice().toInt256(),
            existingOraclePassThrough.getCurrentOraclePrice().toInt256(),
            allowedDeviationArbitrum
        );
    }

    /// swap out the old oracle for the new one and ensure the read functions
    /// give the same value
    function testMintSwapOraclePassThroughOnPSMs(uint96 mintAmount) public {
        vm.assume(mintAmount > 1e18);

        uint256 startingAmountOutDai = daiPSM.getMintAmountOut(mintAmount);
        uint256 startingAmountOutUSDC = usdcPSM.getMintAmountOut(mintAmount);

        vm.warp(startTime - 1 days); /// rewind the clock 1 day so that the timelock execution takes us back to start time

        /// simulate proposal execution so that the next set of assertions can be verified
        /// with new upgrade in place
        simulate(
            getArbitrumProposal(),
            TimelockController(payable(ArbitrumAddresses.TIMELOCK_CONTROLLER)),
            ArbitrumAddresses.GOVERNOR,
            ArbitrumAddresses.EOA_1,
            vm,
            false
        );

        uint256 endingAmountOutDai = daiPSM.getMintAmountOut(mintAmount);
        uint256 endingAmountOutUSDC = usdcPSM.getMintAmountOut(mintAmount);

        assertApproxEq(
            endingAmountOutDai.toInt256(),
            startingAmountOutDai.toInt256(),
            allowedDeviationArbitrum
        );
        assertApproxEq(
            endingAmountOutUSDC.toInt256(),
            startingAmountOutUSDC.toInt256(),
            allowedDeviationArbitrum
        );
    }

    /// swap out the old oracle for the new one and ensure the read functions
    /// give the same value
    function testRedeemSwapOraclePassThroughOnPSMs(uint96 redeemAmount) public {
        vm.assume(redeemAmount > 1e18);
        uint256 startingAmountOutDai = daiPSM.getRedeemAmountOut(redeemAmount);
        uint256 startingAmountOutUSDC = usdcPSM.getRedeemAmountOut(
            redeemAmount
        );

        vm.warp(startTime - 1 days); /// rewind the clock 1 day so that the timelock execution takes us back to start time

        /// simulate proposal execution so that the next set of assertions can be verified
        /// with new upgrade in place
        simulate(
            getArbitrumProposal(),
            TimelockController(payable(ArbitrumAddresses.TIMELOCK_CONTROLLER)),
            ArbitrumAddresses.GOVERNOR,
            ArbitrumAddresses.EOA_1,
            vm,
            false
        );

        uint256 endingAmountOutDai = daiPSM.getRedeemAmountOut(redeemAmount);
        uint256 endingAmountOutUSDC = usdcPSM.getRedeemAmountOut(redeemAmount);

        assertApproxEq(
            endingAmountOutDai.toInt256(),
            startingAmountOutDai.toInt256(),
            allowedDeviationArbitrum
        );
        assertApproxEq(
            endingAmountOutUSDC.toInt256(),
            startingAmountOutUSDC.toInt256(),
            allowedDeviationArbitrum
        );
    }

    /// assert swaps function the same after upgrading the scaling price oracle for Dai
    function testMintParityAfterOracleUpgradeDAI() public {
        uint256 amountStableIn = 101_000;
        uint256 amountVoltOut = daiPSM.getMintAmountOut(amountStableIn);
        uint256 startingUserVoltBalance = volt.balanceOf(address(this));

        IVolt underlyingToken = IVolt(ArbitrumAddresses.DAI);

        vm.prank(ArbitrumAddresses.DAI_MINTER_1); /// fund with DAI
        underlyingToken.mint(address(this), amountStableIn * 2);

        underlyingToken.approve(address(daiPSM), amountStableIn * 2);
        daiPSM.mint(address(this), amountStableIn, amountVoltOut);

        uint256 endingUserVoltBalance = volt.balanceOf(address(this));
        assertEq(
            endingUserVoltBalance,
            startingUserVoltBalance + amountVoltOut
        );

        vm.warp(startTime - 1 days); /// rewind the clock 1 day so that the timelock execution takes us back to start time

        /// simulate proposal execution so that the next set of assertions can be verified
        /// with new upgrade in place
        simulate(
            getArbitrumProposal(),
            TimelockController(payable(ArbitrumAddresses.TIMELOCK_CONTROLLER)),
            ArbitrumAddresses.GOVERNOR,
            ArbitrumAddresses.EOA_1,
            vm,
            false
        );

        uint256 amountVoltOutAfterUpgrade = daiPSM.getMintAmountOut(
            amountStableIn
        );
        uint256 startingUserVoltBalanceAfterUpgrade = volt.balanceOf(
            address(this)
        );

        daiPSM.mint(
            address(this),
            amountStableIn,
            (amountVoltOut *
                (Constants.BASIS_POINTS_GRANULARITY -
                    allowedDeviationArbitrum)) /
                Constants.BASIS_POINTS_GRANULARITY
        );

        uint256 endingUserVoltBalanceAfterUpgrade = volt.balanceOf(
            address(this)
        );
        assertEq(
            endingUserVoltBalanceAfterUpgrade,
            startingUserVoltBalanceAfterUpgrade + amountVoltOutAfterUpgrade
        );
        assertApproxEq(
            amountVoltOutAfterUpgrade.toInt256(),
            amountVoltOut.toInt256(),
            allowedDeviationArbitrum
        );
    }

    /// assert swaps function the same after upgrading the scaling price oracle for USDC
    function testMintParityAfterOracleUpgradeUSDC() public {
        uint256 amountStableIn = 10_100e6;
        uint256 amountVoltOut = usdcPSM.getMintAmountOut(amountStableIn);
        uint256 startingUserVoltBalance = volt.balanceOf(address(this));

        IERC20 underlyingToken = IERC20(ArbitrumAddresses.USDC);

        uint256 underlyingTokenBalance = underlyingToken.balanceOf(
            ArbitrumAddresses.USDC_WHALE
        );
        vm.prank(ArbitrumAddresses.USDC_WHALE);
        underlyingToken.transfer(address(this), underlyingTokenBalance);

        uint256 voltBalance = volt.balanceOf(ArbitrumAddresses.GOVERNOR);
        vm.prank(ArbitrumAddresses.GOVERNOR);
        volt.transfer(address(usdcPSM), voltBalance);

        underlyingToken.approve(address(usdcPSM), amountStableIn * 2);
        usdcPSM.mint(address(this), amountStableIn, amountVoltOut);

        uint256 endingUserVoltBalance = volt.balanceOf(address(this));
        assertEq(
            endingUserVoltBalance,
            startingUserVoltBalance + amountVoltOut
        );

        vm.warp(startTime - 1 days); /// rewind the clock 1 day so that the timelock execution takes us back to start time

        /// simulate proposal execution so that the next set of assertions can be verified
        /// with new upgrade in place
        simulate(
            getArbitrumProposal(),
            TimelockController(payable(ArbitrumAddresses.TIMELOCK_CONTROLLER)),
            ArbitrumAddresses.GOVERNOR,
            ArbitrumAddresses.EOA_1,
            vm,
            false
        );

        uint256 amountVoltOutAfterUpgrade = usdcPSM.getMintAmountOut(
            amountStableIn
        );
        uint256 startingUserVoltBalanceAfterUpgrade = volt.balanceOf(
            address(this)
        );

        usdcPSM.mint(
            address(this),
            amountStableIn,
            (amountVoltOut *
                (Constants.BASIS_POINTS_GRANULARITY -
                    allowedDeviationArbitrum)) /
                Constants.BASIS_POINTS_GRANULARITY
        );

        uint256 endingUserVoltBalanceAfterUpgrade = volt.balanceOf(
            address(this)
        );
        assertEq(
            endingUserVoltBalanceAfterUpgrade,
            startingUserVoltBalanceAfterUpgrade + amountVoltOutAfterUpgrade
        );
        assertApproxEq(
            amountVoltOutAfterUpgrade.toInt256(),
            amountVoltOut.toInt256(),
            allowedDeviationArbitrum
        );
    }

    /// assert redemptions function the same after upgrading the scaling price oracle for Dai
    function testRedeemParityAfterOracleUpgradeDAI() public {
        uint256 amountVoltIn = 1_000e18;
        vm.prank(ArbitrumAddresses.GOVERNOR); /// fund with Volt
        volt.transfer(address(this), amountVoltIn * 2);

        uint256 amountDaiOut = daiPSM.getRedeemAmountOut(amountVoltIn);
        uint256 startingUserDaiBalance = dai.balanceOf(address(this));

        volt.approve(address(daiPSM), amountVoltIn * 2);
        daiPSM.redeem(address(this), amountVoltIn, amountDaiOut);

        uint256 endingUserDaiBalance = dai.balanceOf(address(this));
        assertEq(endingUserDaiBalance, startingUserDaiBalance + amountDaiOut);

        vm.warp(startTime - 1 days); /// rewind the clock 1 day so that the timelock execution takes us back to start time

        /// simulate proposal execution so that the next set of assertions can be verified
        /// with new upgrade in place
        simulate(
            getArbitrumProposal(),
            TimelockController(payable(ArbitrumAddresses.TIMELOCK_CONTROLLER)),
            ArbitrumAddresses.GOVERNOR,
            ArbitrumAddresses.EOA_1,
            vm,
            false
        );

        uint256 amountDaiOutAfterUpgrade = daiPSM.getRedeemAmountOut(
            amountVoltIn
        );
        uint256 startingUserDaiBalanceAfterUpgrade = dai.balanceOf(
            address(this)
        );

        daiPSM.redeem(address(this), amountVoltIn, amountDaiOutAfterUpgrade);

        uint256 endingUserDaiBalanceAfterUpgrade = dai.balanceOf(address(this));
        assertEq(
            endingUserDaiBalanceAfterUpgrade,
            startingUserDaiBalanceAfterUpgrade + amountDaiOutAfterUpgrade
        );
        assertApproxEq(
            amountDaiOutAfterUpgrade.toInt256(),
            amountDaiOut.toInt256(),
            allowedDeviationArbitrum
        );
        assertTrue(amountDaiOutAfterUpgrade > amountDaiOut); /// Oracle Price increased
    }

    /// assert redemptions function the same after upgrading the scaling price oracle for Usdc
    function testRedeemParityAfterOracleUpgradeUSDC() public {
        if (usdcPSM.redeemPaused()) {
            vm.prank(ArbitrumAddresses.PCV_GUARDIAN);
            usdcPSM.unpauseRedeem();
        }

        uint256 amountVoltIn = 1_000e18;
        vm.prank(ArbitrumAddresses.GOVERNOR); /// fund with Volt
        volt.transfer(address(this), amountVoltIn * 2);

        uint256 amountUsdcOut = usdcPSM.getRedeemAmountOut(amountVoltIn);
        uint256 startingUserUsdcBalance = usdc.balanceOf(address(this));

        volt.approve(address(usdcPSM), amountVoltIn * 2);
        usdcPSM.redeem(address(this), amountVoltIn, amountUsdcOut);

        uint256 endingUserUsdcBalance = usdc.balanceOf(address(this));
        assertEq(
            endingUserUsdcBalance,
            startingUserUsdcBalance + amountUsdcOut
        );

        vm.warp(startTime - 1 days); /// rewind the clock 1 day so that the timelock execution takes us back to start time

        /// simulate proposal execution so that the next set of assertions can be verified
        /// with new upgrade in place
        simulate(
            getArbitrumProposal(),
            TimelockController(payable(ArbitrumAddresses.TIMELOCK_CONTROLLER)),
            ArbitrumAddresses.GOVERNOR,
            ArbitrumAddresses.EOA_1,
            vm,
            false
        );

        uint256 amountUsdcOutAfterUpgrade = usdcPSM.getRedeemAmountOut(
            amountVoltIn
        );
        uint256 startingUserUsdcBalanceAfterUpgrade = usdc.balanceOf(
            address(this)
        );

        usdcPSM.redeem(address(this), amountVoltIn, amountUsdcOutAfterUpgrade);

        uint256 endingUserUsdcBalanceAfterUpgrade = usdc.balanceOf(
            address(this)
        );
        assertEq(
            endingUserUsdcBalanceAfterUpgrade,
            startingUserUsdcBalanceAfterUpgrade + amountUsdcOutAfterUpgrade
        );
        assertApproxEq(
            amountUsdcOutAfterUpgrade.toInt256(),
            amountUsdcOut.toInt256(),
            allowedDeviationArbitrum
        );
        assertTrue(amountUsdcOutAfterUpgrade > amountUsdcOut); /// Oracle Price increased with upgrade
    }

    function testSetMintFee() public {
        vm.warp(startTime - 1 days); /// rewind the clock 1 day so that the timelock execution takes us back to start time

        /// simulate proposal execution so that the next set of assertions can be verified
        /// with new upgrade in place
        simulate(
            getArbitrumProposal(),
            TimelockController(payable(ArbitrumAddresses.TIMELOCK_CONTROLLER)),
            ArbitrumAddresses.GOVERNOR,
            ArbitrumAddresses.EOA_1,
            vm,
            false
        );

        uint256 endingFeeDai = daiPSM.mintFeeBasisPoints();
        uint256 endingFeeUsdc = usdcPSM.mintFeeBasisPoints();

        assertEq(endingFeeDai, 5);
        assertEq(endingFeeUsdc, 5);
    }
}
