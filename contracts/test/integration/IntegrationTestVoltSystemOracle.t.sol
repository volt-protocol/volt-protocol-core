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
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {Constants} from "../../Constants.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVolt} from "../../volt/IVolt.sol";

contract IntegrationTestVoltSystemOracle is DSTest {
    using Decimal for Decimal.D256;
    using SafeCast for *;

    /// @notice reference to Volt
    IERC20 private volt = IERC20(MainnetAddresses.VOLT);

    /// @notice scaling price oracle on mainnet today
    ScalingPriceOracle private scalingPriceOracle =
        ScalingPriceOracle(MainnetAddresses.SCALING_PRICE_ORACLE);

    /// @notice new Volt System Oracle
    VoltSystemOracle private voltSystemOracle;

    /// @notice new Oracle Pass Through
    OraclePassThrough private oraclePassThrough;

    /// @notice existing Oracle Pass Through deployed on mainnet
    OraclePassThrough private immutable existingOraclePassThrough =
        OraclePassThrough(MainnetAddresses.ORACLE_PASS_THROUGH);

    /// @notice increase price by x% per month
    uint256 public constant annualChangeRateBasisPoints = 200;

    /// @notice fei volt PSM
    PriceBoundPSM private immutable feiPSM =
        PriceBoundPSM(MainnetAddresses.VOLT_FEI_PSM);

    /// @notice usdc volt PSM
    PriceBoundPSM private immutable usdcPSM =
        PriceBoundPSM(MainnetAddresses.VOLT_USDC_PSM);

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
        uint256 startingAmountOutFei = feiPSM.getMintAmountOut(mintAmount);
        uint256 startingAmountOutUSDC = usdcPSM.getMintAmountOut(mintAmount);

        vm.startPrank(MainnetAddresses.GOVERNOR);
        feiPSM.setOracle(address(oraclePassThrough));
        usdcPSM.setOracle(address(oraclePassThrough));
        vm.stopPrank();

        uint256 endingAmountOutFei = feiPSM.getMintAmountOut(mintAmount);
        uint256 endingAmountOutUSDC = usdcPSM.getMintAmountOut(mintAmount);

        assertEq(endingAmountOutFei, startingAmountOutFei);
        assertEq(endingAmountOutUSDC, startingAmountOutUSDC);
    }

    /// swap out the old oracle for the new one and ensure the read functions
    /// give the same value
    function testRedeemSwapOraclePassThroughOnPSMs() public {
        _warpToStart();

        uint256 redeemAmount = 100_000e18;
        uint256 startingAmountOutFei = feiPSM.getRedeemAmountOut(redeemAmount);
        uint256 startingAmountOutUSDC = usdcPSM.getRedeemAmountOut(
            redeemAmount
        );

        vm.startPrank(MainnetAddresses.GOVERNOR);
        feiPSM.setOracle(address(oraclePassThrough));
        usdcPSM.setOracle(address(oraclePassThrough));
        vm.stopPrank();

        uint256 endingAmountOutFei = feiPSM.getRedeemAmountOut(redeemAmount);
        uint256 endingAmountOutUSDC = usdcPSM.getRedeemAmountOut(redeemAmount);

        assertEq(endingAmountOutFei, startingAmountOutFei);
        assertEq(endingAmountOutUSDC, startingAmountOutUSDC);
    }

    /// assert swaps function the same after upgrading the scaling price oracle for Fei
    function testMintParityAfterOracleUpgradeFEI() public {
        _warpToStart();
        uint256 amountStableIn = 101_000;
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

        vm.prank(MainnetAddresses.GOVERNOR);
        feiPSM.setOracle(address(oraclePassThrough));

        uint256 amountVoltOutAfterUpgrade = feiPSM.getMintAmountOut(
            amountStableIn
        );
        uint256 startingUserVoltBalanceAfterUpgrade = volt.balanceOf(
            address(this)
        );

        feiPSM.mint(address(this), amountStableIn, amountVoltOut);

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

        vm.prank(MainnetAddresses.GOVERNOR);
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
}
