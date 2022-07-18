// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Vm} from "./../unit/utils/Vm.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {getCore, getAddresses, VoltTestAddresses} from "./../unit/utils/Fixtures.sol";
import {Decimal} from "./../../external/Decimal.sol";
import {PriceBoundPSM} from "./../../peg/PriceBoundPSM.sol";
import {IScalingPriceOracle, ScalingPriceOracle} from "./../../oracle/ScalingPriceOracle.sol";
import {VoltSystemOracle} from "./../../oracle/VoltSystemOracle.sol";
import {OraclePassThrough} from "./../../oracle/OraclePassThrough.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ArbitrumAddresses} from "./fixtures/ArbitrumAddresses.sol";
import {Constants} from "../../Constants.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVolt} from "../../volt/IVolt.sol";

contract ArbitrumTestVoltSystemOracle is DSTest {
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
        ScalingPriceOracle(ArbitrumAddresses.SCALING_PRICE_ORACLE);

    /// @notice new Volt System Oracle
    VoltSystemOracle private voltSystemOracle;

    /// @notice new Oracle Pass Through
    OraclePassThrough private oraclePassThrough;

    /// @notice existing Oracle Pass Through deployed on mainnet
    OraclePassThrough private immutable existingOraclePassThrough =
        OraclePassThrough(ArbitrumAddresses.ORACLE_PASS_THROUGH);

    /// @notice increase price by x% per month
    uint256 public constant annualChangeRateBasisPoints = 200;

    /// @notice dai volt PSM
    PriceBoundPSM private immutable daiPSM =
        PriceBoundPSM(ArbitrumAddresses.VOLT_DAI_PSM);

    /// @notice usdc volt PSM
    PriceBoundPSM private immutable usdcPSM =
        PriceBoundPSM(ArbitrumAddresses.VOLT_USDC_PSM);

    /// @notice starting price of the current mainnet scaling price oracle
    uint256 public startOraclePrice = scalingPriceOracle.oraclePrice();

    Vm public constant vm = Vm(HEVM_ADDRESS);
    VoltTestAddresses public addresses = getAddresses();

    function setUp() public {
        uint256 spoStartPrice = scalingPriceOracle.oraclePrice();
        /// monthly change rate is positive as of 6/29/2022,
        /// not expecting deflation anytime soon
        uint256 monthlyChangeRateBasisPoints = scalingPriceOracle
            .monthlyChangeRateBasisPoints()
            .toUint256();
        uint256 spoEndPrice = (spoStartPrice *
            (monthlyChangeRateBasisPoints +
                Constants.BASIS_POINTS_GRANULARITY)) /
            Constants.BASIS_POINTS_GRANULARITY;

        voltSystemOracle = new VoltSystemOracle(
            annualChangeRateBasisPoints,
            scalingPriceOracle.startTime() + scalingPriceOracle.TIMEFRAME(),
            spoEndPrice
        );

        oraclePassThrough = new OraclePassThrough(
            IScalingPriceOracle(address(voltSystemOracle))
        );
    }

    function _warpToStart() internal {
        vm.warp(
            scalingPriceOracle.startTime() + scalingPriceOracle.TIMEFRAME()
        );
    }

    function testSetup() public {
        assertEq(
            address(oraclePassThrough.scalingPriceOracle()),
            address(voltSystemOracle)
        );
    }

    function testPriceEquivalenceAtTermEnd() public {
        _warpToStart();
        assertEq(
            scalingPriceOracle.getCurrentOraclePrice(),
            voltSystemOracle.getCurrentOraclePrice()
        );
        assertEq(
            voltSystemOracle.oraclePrice(),
            voltSystemOracle.getCurrentOraclePrice()
        );
        assertEq(
            oraclePassThrough.getCurrentOraclePrice(),
            existingOraclePassThrough.getCurrentOraclePrice()
        );
    }

    /// swap out the old oracle for the new one and ensure the read functions
    /// give the same value
    function testMintSwapOraclePassThroughOnPSMs() public {
        _warpToStart();

        uint256 mintAmount = 100_000e18;
        uint256 startingAmountOutDai = daiPSM.getMintAmountOut(mintAmount);
        uint256 startingAmountOutUSDC = usdcPSM.getMintAmountOut(mintAmount);

        vm.startPrank(ArbitrumAddresses.GOVERNOR);
        daiPSM.setOracle(address(oraclePassThrough));
        usdcPSM.setOracle(address(oraclePassThrough));
        vm.stopPrank();

        uint256 endingAmountOutDai = daiPSM.getMintAmountOut(mintAmount);
        uint256 endingAmountOutUSDC = usdcPSM.getMintAmountOut(mintAmount);

        assertEq(endingAmountOutDai, startingAmountOutDai);
        assertEq(endingAmountOutUSDC, startingAmountOutUSDC);
    }

    /// swap out the old oracle for the new one and ensure the read functions
    /// give the same value
    function testRedeemSwapOraclePassThroughOnPSMs() public {
        _warpToStart();

        uint256 redeemAmount = 100_000e18;
        uint256 startingAmountOutDai = daiPSM.getRedeemAmountOut(redeemAmount);
        uint256 startingAmountOutUSDC = usdcPSM.getRedeemAmountOut(
            redeemAmount
        );

        vm.startPrank(ArbitrumAddresses.GOVERNOR);
        daiPSM.setOracle(address(oraclePassThrough));
        usdcPSM.setOracle(address(oraclePassThrough));
        vm.stopPrank();

        uint256 endingAmountOutDai = daiPSM.getRedeemAmountOut(redeemAmount);
        uint256 endingAmountOutUSDC = usdcPSM.getRedeemAmountOut(redeemAmount);

        assertEq(endingAmountOutDai, startingAmountOutDai);
        assertEq(endingAmountOutUSDC, startingAmountOutUSDC);
    }

    /// assert swaps function the same after upgrading the scaling price oracle for Dai
    function testMintParityAfterOracleUpgradeDAI() public {
        _warpToStart();
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

        vm.prank(ArbitrumAddresses.GOVERNOR);
        daiPSM.setOracle(address(oraclePassThrough));

        uint256 amountVoltOutAfterUpgrade = daiPSM.getMintAmountOut(
            amountStableIn
        );
        uint256 startingUserVoltBalanceAfterUpgrade = volt.balanceOf(
            address(this)
        );

        daiPSM.mint(address(this), amountStableIn, amountVoltOut);

        uint256 endingUserVoltBalanceAfterUpgrade = volt.balanceOf(
            address(this)
        );
        assertEq(
            endingUserVoltBalanceAfterUpgrade,
            startingUserVoltBalanceAfterUpgrade + amountVoltOutAfterUpgrade
        );
        assertEq(amountVoltOutAfterUpgrade, amountVoltOut);
    }

    /// assert swaps function the same after upgrading the scaling price oracle for USDC
    function testMintParityAfterOracleUpgradeUSDC() public {
        _warpToStart();
        uint256 amountStableIn = 10_100e6;
        uint256 amountVoltOut = usdcPSM.getMintAmountOut(amountStableIn);
        uint256 startingUserVoltBalance = volt.balanceOf(address(this));

        IERC20 underlyingToken = IERC20(ArbitrumAddresses.USDC);

        uint256 underlyingTokenBalance = underlyingToken.balanceOf(
            ArbitrumAddresses.USDC_WHALE
        );
        vm.prank(ArbitrumAddresses.USDC_WHALE);
        underlyingToken.transfer(address(this), underlyingTokenBalance);

        uint256 voltBalance = volt.balanceOf(ArbitrumAddresses.VOLT_DAI_PSM);
        vm.prank(ArbitrumAddresses.VOLT_DAI_PSM);
        volt.transfer(address(usdcPSM), voltBalance);

        underlyingToken.approve(address(usdcPSM), amountStableIn * 2);
        usdcPSM.mint(address(this), amountStableIn, amountVoltOut);

        uint256 endingUserVoltBalance = volt.balanceOf(address(this));
        assertEq(
            endingUserVoltBalance,
            startingUserVoltBalance + amountVoltOut
        );

        vm.prank(ArbitrumAddresses.GOVERNOR);
        usdcPSM.setOracle(address(oraclePassThrough));

        uint256 amountVoltOutAfterUpgrade = usdcPSM.getMintAmountOut(
            amountStableIn
        );
        uint256 startingUserVoltBalanceAfterUpgrade = volt.balanceOf(
            address(this)
        );

        usdcPSM.mint(address(this), amountStableIn, amountVoltOut);

        uint256 endingUserVoltBalanceAfterUpgrade = volt.balanceOf(
            address(this)
        );
        assertEq(
            endingUserVoltBalanceAfterUpgrade,
            startingUserVoltBalanceAfterUpgrade + amountVoltOutAfterUpgrade
        );
        assertEq(amountVoltOutAfterUpgrade, amountVoltOut);
    }

    /// assert redemptions function the same after upgrading the scaling price oracle for Dai
    function testRedeemParityAfterOracleUpgradeDAI() public {
        _warpToStart();

        uint256 amountVoltIn = 1_000e18;
        vm.prank(ArbitrumAddresses.VOLT_DAI_PSM); /// fund with Volt
        volt.transfer(address(this), amountVoltIn * 2);

        uint256 amountDaiOut = daiPSM.getRedeemAmountOut(amountVoltIn);
        uint256 startingUserDaiBalance = dai.balanceOf(address(this));

        volt.approve(address(daiPSM), amountVoltIn * 2);
        daiPSM.redeem(address(this), amountVoltIn, amountDaiOut);

        uint256 endingUserDaiBalance = dai.balanceOf(address(this));
        assertEq(endingUserDaiBalance, startingUserDaiBalance + amountDaiOut);

        vm.prank(ArbitrumAddresses.GOVERNOR);
        daiPSM.setOracle(address(oraclePassThrough));

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
        assertEq(amountDaiOutAfterUpgrade, amountDaiOut);
    }

    /// assert redemptions function the same after upgrading the scaling price oracle for Usdc
    function testRedeemParityAfterOracleUpgradeUSDC() public {
        _warpToStart();
        if (usdcPSM.redeemPaused()) {
            vm.prank(ArbitrumAddresses.GUARDIAN);
            usdcPSM.unpauseRedeem();
        }

        uint256 amountVoltIn = 1_000e18;
        vm.prank(ArbitrumAddresses.VOLT_DAI_PSM); /// fund with Volt
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

        vm.prank(ArbitrumAddresses.GOVERNOR);
        usdcPSM.setOracle(address(oraclePassThrough));

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
        assertEq(amountUsdcOutAfterUpgrade, amountUsdcOut);
    }

    function testSetMintFee() public {
        uint256 startingFeeDai = daiPSM.mintFeeBasisPoints();
        uint256 startingFeeUsdc = usdcPSM.mintFeeBasisPoints();

        /// if starting fee is 5 bips, no need to run this test as upgrade has been applied
        if (startingFeeDai == 5 && startingFeeUsdc == 5) {
            return;
        }

        vm.startPrank(ArbitrumAddresses.TIMELOCK);
        usdcPSM.setMintFee(5);
        daiPSM.setMintFee(5);
        vm.stopPrank();

        uint256 endingFeeDai = daiPSM.mintFeeBasisPoints();
        uint256 endingFeeUsdc = usdcPSM.mintFeeBasisPoints();

        assertEq(startingFeeDai, 50);
        assertEq(startingFeeUsdc, 50);
        assertEq(endingFeeDai, 5);
        assertEq(endingFeeUsdc, 5);
    }
}
