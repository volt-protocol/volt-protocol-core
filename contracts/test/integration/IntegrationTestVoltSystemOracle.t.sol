// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "./../unit/utils/Vm.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {Decimal} from "./../../external/Decimal.sol";
import {PriceBoundPSM} from "./../../peg/PriceBoundPSM.sol";
import {IScalingPriceOracle, ScalingPriceOracle} from "./../../oracle/ScalingPriceOracle.sol";
import {VoltSystemOracle} from "./../../oracle/VoltSystemOracle.sol";
import {OraclePassThrough} from "./../../oracle/OraclePassThrough.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {Constants} from "../../Constants.sol";
import {IVolt} from "../../volt/IVolt.sol";
import {TimelockSimulation} from "./utils/TimelockSimulation.sol";
import {vip2} from "./vip/vip2.sol";

contract IntegrationTestVoltSystemOracle is TimelockSimulation, vip2 {
    using Decimal for Decimal.D256;
    using SafeCast for *;

    /// @notice reference to Volt
    IVolt private volt = IVolt(MainnetAddresses.VOLT);

    /// @notice reference to Fei
    IERC20 private fei = IERC20(MainnetAddresses.FEI);

    /// @notice reference to USDC
    IERC20 private usdc = IERC20(MainnetAddresses.USDC);

    /// @notice scaling price oracle on mainnet today
    ScalingPriceOracle private scalingPriceOracle =
        ScalingPriceOracle(MainnetAddresses.DEPRECATED_SCALING_PRICE_ORACLE);

    /// @notice existing Oracle Pass Through deployed on mainnet
    OraclePassThrough private immutable existingOraclePassThrough =
        OraclePassThrough(MainnetAddresses.DEPRECATED_ORACLE_PASS_THROUGH);

    /// @notice new Volt System Oracle
    VoltSystemOracle private voltSystemOracle =
        VoltSystemOracle(MainnetAddresses.VOLT_SYSTEM_ORACLE);

    /// @notice new Oracle Pass Through
    OraclePassThrough private oraclePassThrough =
        OraclePassThrough(MainnetAddresses.ORACLE_PASS_THROUGH);

    /// @notice fei volt PSM
    PriceBoundPSM private immutable feiPSM =
        PriceBoundPSM(MainnetAddresses.VOLT_FEI_PSM);

    /// @notice usdc volt PSM
    PriceBoundPSM private immutable usdcPSM =
        PriceBoundPSM(MainnetAddresses.VOLT_USDC_PSM);

    /// @notice new Volt System Oracle start time
    uint256 constant startTime = 1659467776;

    function setUp() public {
        /// set mint fees to 0 so that the only change that is measured is the
        /// difference between oracle prices
        vm.startPrank(MainnetAddresses.GOVERNOR);
        feiPSM.setMintFee(0);
        usdcPSM.setMintFee(0);
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
            allowedDeviation
        );
        /// because start time is a little past when the calculated start time would be,
        /// there is a slight but non zero deviation (976 seconds of unnacrued interest)
        assertApproxEq(
            voltSystemOracle.oraclePrice().toInt256(),
            voltSystemOracle.getCurrentOraclePrice().toInt256(),
            0
        );
        assertApproxEq(
            oraclePassThrough.getCurrentOraclePrice().toInt256(),
            existingOraclePassThrough.getCurrentOraclePrice().toInt256(),
            allowedDeviation
        );
    }

    /// swap out the old oracle for the new one and ensure the read functions
    /// give the same value
    function testMintSwapOraclePassThroughOnPSMs(uint96 mintAmount) public {
        vm.assume(mintAmount > 1e18);

        uint256 startingAmountOutFei = feiPSM.getMintAmountOut(mintAmount);
        uint256 startingAmountOutUSDC = usdcPSM.getMintAmountOut(mintAmount);

        vm.warp(startTime - 1 days); /// rewind the clock 1 day so that the timelock execution takes us back to start time

        /// simulate proposal execution so that the next set of assertions can be verified
        /// with new upgrade in place
        simulate(
            getMainnetProposal(),
            TimelockController(payable(MainnetAddresses.TIMELOCK_CONTROLLER)),
            MainnetAddresses.GOVERNOR,
            MainnetAddresses.EOA_1,
            vm,
            false
        );

        uint256 endingAmountOutFei = feiPSM.getMintAmountOut(mintAmount);
        uint256 endingAmountOutUSDC = usdcPSM.getMintAmountOut(mintAmount);

        assertApproxEq(
            endingAmountOutFei.toInt256(),
            startingAmountOutFei.toInt256(),
            allowedDeviation
        );
        assertApproxEq(
            endingAmountOutUSDC.toInt256(),
            startingAmountOutUSDC.toInt256(),
            allowedDeviation
        );
    }

    /// swap out the old oracle for the new one and ensure the read functions
    /// give the same value
    function testRedeemSwapOraclePassThroughOnPSMs(uint96 redeemAmount) public {
        vm.assume(redeemAmount > 1e18);

        uint256 startingAmountOutFei = feiPSM.getRedeemAmountOut(redeemAmount);
        uint256 startingAmountOutUSDC = usdcPSM.getRedeemAmountOut(
            redeemAmount
        );

        vm.warp(startTime - 1 days); /// rewind the clock 1 day so that the timelock execution takes us back to start time

        /// simulate proposal execution so that the next set of assertions can be verified
        /// with new upgrade in place
        simulate(
            getMainnetProposal(),
            TimelockController(payable(MainnetAddresses.TIMELOCK_CONTROLLER)),
            MainnetAddresses.GOVERNOR,
            MainnetAddresses.EOA_1,
            vm,
            false
        );

        uint256 endingAmountOutFei = feiPSM.getRedeemAmountOut(redeemAmount);
        uint256 endingAmountOutUSDC = usdcPSM.getRedeemAmountOut(redeemAmount);

        assertApproxEq(
            endingAmountOutFei.toInt256(),
            startingAmountOutFei.toInt256(),
            allowedDeviation
        );
        assertApproxEq(
            endingAmountOutUSDC.toInt256(),
            startingAmountOutUSDC.toInt256(),
            allowedDeviation
        );
    }

    /// assert swaps function the same after upgrading the scaling price oracle for Fei
    function testMintParityAfterOracleUpgradeFEI() public {
        uint256 amountStableIn = 101_000e18;
        uint256 amountVoltOut = feiPSM.getMintAmountOut(amountStableIn);
        uint256 startingUserVoltBalance = volt.balanceOf(address(this));

        IVolt underlyingToken = IVolt(MainnetAddresses.FEI);

        vm.prank(MainnetAddresses.FEI_DAO_TIMELOCK); /// fund with Fei
        underlyingToken.mint(address(this), amountStableIn * 2);

        underlyingToken.approve(address(feiPSM), amountStableIn * 2);
        feiPSM.mint(address(this), amountStableIn, amountVoltOut);

        uint256 endingUserVoltBalance = volt.balanceOf(address(this));
        assertEq(
            endingUserVoltBalance,
            startingUserVoltBalance + amountVoltOut
        );

        vm.warp(startTime - 1 days); /// rewind the clock 1 day so that the timelock execution takes us back to start time

        /// simulate proposal execution so that the next set of assertions can be verified
        /// with new upgrade in place
        simulate(
            getMainnetProposal(),
            TimelockController(payable(MainnetAddresses.TIMELOCK_CONTROLLER)),
            MainnetAddresses.GOVERNOR,
            MainnetAddresses.EOA_1,
            vm,
            false
        );

        assertEq(address(oraclePassThrough), address(feiPSM.oracle()));

        uint256 amountVoltOutAfterUpgrade = feiPSM.getMintAmountOut(
            amountStableIn
        );
        uint256 startingUserVoltBalanceAfterUpgrade = volt.balanceOf(
            address(this)
        );

        /// apply 6 bip haircut to amount volt out as price increased by 5 bips when oracle swap happens
        feiPSM.mint(
            address(this),
            amountStableIn,
            (amountVoltOut * (10_000 - allowedDeviation)) / 10_000
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
            allowedDeviation
        );
    }

    /// assert swaps function the same after upgrading the scaling price oracle for USDC
    function testMintParityAfterOracleUpgradeUSDC() public {
        uint256 amountStableIn = 101_000;
        uint256 amountVoltOut = usdcPSM.getMintAmountOut(amountStableIn);
        uint256 startingUserVoltBalance = volt.balanceOf(address(this));

        IERC20 underlyingToken = IERC20(MainnetAddresses.USDC);

        vm.prank(MainnetAddresses.MAKER_USDC_PSM);
        underlyingToken.transfer(address(this), amountStableIn * 2);

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
            getMainnetProposal(),
            TimelockController(payable(MainnetAddresses.TIMELOCK_CONTROLLER)),
            MainnetAddresses.GOVERNOR,
            MainnetAddresses.EOA_1,
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
            (amountVoltOut * (10_000 - allowedDeviation)) / 10_000
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
            allowedDeviation
        );
    }

    /// assert redemptions function the same after upgrading the scaling price oracle for Fei
    function testRedeemParityAfterOracleUpgradeFEI() public {
        uint256 amountVoltIn = 10_000e18;

        vm.prank(MainnetAddresses.CORE);
        Core(MainnetAddresses.CORE).grantMinter(MainnetAddresses.CORE);

        vm.prank(MainnetAddresses.CORE); /// fund with VOLT
        volt.mint(address(this), amountVoltIn * 2);

        uint256 amountFeiOut = feiPSM.getRedeemAmountOut(amountVoltIn);
        uint256 startingUserFeiBalance = fei.balanceOf(address(this));

        volt.approve(address(feiPSM), amountVoltIn * 2);
        feiPSM.redeem(address(this), amountVoltIn, amountFeiOut);

        uint256 endingUserFeiBalance = fei.balanceOf(address(this));
        assertEq(endingUserFeiBalance, startingUserFeiBalance + amountFeiOut);

        vm.warp(startTime - 1 days); /// rewind the clock 1 day so that the timelock execution takes us back to start time

        /// simulate proposal execution so that the next set of assertions can be verified
        /// with new upgrade in place
        simulate(
            getMainnetProposal(),
            TimelockController(payable(MainnetAddresses.TIMELOCK_CONTROLLER)),
            MainnetAddresses.GOVERNOR,
            MainnetAddresses.EOA_1,
            vm,
            false
        );

        uint256 amountFeiOutAfterUpgrade = feiPSM.getRedeemAmountOut(
            amountVoltIn
        );
        uint256 startingUserFeiBalanceAfterUpgrade = fei.balanceOf(
            address(this)
        );

        feiPSM.redeem(address(this), amountVoltIn, amountFeiOutAfterUpgrade);

        uint256 endingUserFeiBalanceAfterUpgrade = fei.balanceOf(address(this));
        assertEq(
            endingUserFeiBalanceAfterUpgrade,
            startingUserFeiBalanceAfterUpgrade + amountFeiOutAfterUpgrade
        );
        assertApproxEq(
            amountFeiOutAfterUpgrade.toInt256(),
            amountFeiOut.toInt256(),
            allowedDeviation
        );
    }

    /// assert redemptions function the same after upgrading the scaling price oracle for Usdc
    function testRedeemParityAfterOracleUpgradeUSDC() public {
        if (usdcPSM.redeemPaused()) {
            vm.prank(MainnetAddresses.PCV_GUARDIAN);
            usdcPSM.unpauseRedeem();
        }

        uint256 amountVoltIn = 10_000e18;
        vm.prank(MainnetAddresses.CORE);
        Core(MainnetAddresses.CORE).grantMinter(MainnetAddresses.CORE);

        vm.prank(MainnetAddresses.CORE); /// fund with VOLT
        volt.mint(address(this), amountVoltIn * 2);

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
            getMainnetProposal(),
            TimelockController(payable(MainnetAddresses.TIMELOCK_CONTROLLER)),
            MainnetAddresses.GOVERNOR,
            MainnetAddresses.EOA_1,
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
            allowedDeviation
        );
    }

    function testSetMintFee() public {
        vm.warp(startTime - 1 days); /// rewind the clock 1 day so that the timelock execution takes us back to start time

        /// simulate proposal execution so that the next set of assertions can be verified
        /// with new upgrade in place
        simulate(
            getMainnetProposal(),
            TimelockController(payable(MainnetAddresses.TIMELOCK_CONTROLLER)),
            MainnetAddresses.GOVERNOR,
            MainnetAddresses.EOA_1,
            vm,
            false
        );

        uint256 endingFeeFei = feiPSM.mintFeeBasisPoints();
        uint256 endingFeeUsdc = usdcPSM.mintFeeBasisPoints();

        assertEq(endingFeeFei, 0);
        assertEq(endingFeeUsdc, 0);
    }
}
