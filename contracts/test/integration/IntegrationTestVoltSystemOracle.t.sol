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

contract IntegrationTestVoltSystemOracle is DSTest {
    using Decimal for Decimal.D256;
    using SafeCast for *;

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

    function testSetup() public {
        assertEq(
            address(oraclePassThrough.scalingPriceOracle()),
            address(voltSystemOracle)
        );
    }

    function testPriceEquivalenceAtTermEnd() public {
        vm.warp(
            scalingPriceOracle.startTime() + scalingPriceOracle.TIMEFRAME()
        );
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

    function testSwapOraclePassThroughOnPSMs() public {}
}
