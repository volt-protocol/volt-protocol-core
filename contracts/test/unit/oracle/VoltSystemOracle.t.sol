// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Vm} from "./../utils/Vm.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {MockScalingPriceOracle} from "../../../mock/MockScalingPriceOracle.sol";
import {VoltSystemOracle} from "../../../oracle/VoltSystemOracle.sol";
import {ScalingPriceOracle} from "../../../oracle/ScalingPriceOracle.sol";
import {MockChainlinkToken} from "../../../mock/MockChainlinkToken.sol";
import {Decimal} from "./../../../external/Decimal.sol";
import {Constants} from "./../../../Constants.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract VoltSystemOracleUnitTest is DSTest {
    using Decimal for Decimal.D256;
    using SafeCast for *;

    /// @notice reference to the volt system oracle
    VoltSystemOracle private voltSystemOracle;

    /// @notice increase the volt target price by 2% monthly
    uint256 public constant monthlyChangeRateBasisPoints = 200;

    /// @notice block time at which the VSO (Volt System Oracle) will start accruing interest
    uint256 public constant startTime = 100_000;

    /// @notice actual starting oracle price on mainnet
    uint256 public constant startPrice = 1045095352308302897;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    function setUp() public {
        voltSystemOracle = new VoltSystemOracle(
            monthlyChangeRateBasisPoints,
            startTime,
            startPrice
        );
    }

    function testSetup() public {
        assertEq(voltSystemOracle.oraclePrice(), startPrice);
        assertEq(
            voltSystemOracle.monthlyChangeRateBasisPoints(),
            monthlyChangeRateBasisPoints
        );
        assertEq(voltSystemOracle.periodStartTime(), startTime);
        assertEq(voltSystemOracle.getCurrentOraclePrice(), startPrice);
    }

    function testCompoundBeforePeriodStartFails() public {
        vm.expectRevert("VoltSystemOracle: not past end time");
        voltSystemOracle.compoundInterest();
    }

    function _testLERP(uint256 lerpStartTime) internal {
        vm.warp(lerpStartTime);

        uint256 oraclePrice = voltSystemOracle.oraclePrice();
        uint256 endingOraclePrice = _calculateDelta(
            oraclePrice,
            monthlyChangeRateBasisPoints + Constants.BASIS_POINTS_GRANULARITY
        );
        uint256 periodStartTime = voltSystemOracle.periodStartTime();
        uint256 expectedOraclePrice = _calculateLinearInterpolation(
            block.timestamp, /// calculate interest accrued at this point in time
            periodStartTime, /// x1
            periodStartTime + voltSystemOracle.TIMEFRAME(), /// x2
            oraclePrice, /// y1
            endingOraclePrice /// y2
        );
        assertEq(voltSystemOracle.getCurrentOraclePrice(), expectedOraclePrice);
    }

    function testLERPPerDay() public {
        vm.warp(block.timestamp + voltSystemOracle.periodStartTime());
        for (uint256 i = 1; i < voltSystemOracle.TIMEFRAME() / 1 days; i++) {
            _testLERP(block.timestamp + 1 days);
        }
    }

    function testCompoundSucceedsAfterOnePeriod() public {
        vm.warp(
            block.timestamp +
                voltSystemOracle.periodStartTime() +
                voltSystemOracle.TIMEFRAME()
        );

        uint256 oraclePrice = voltSystemOracle.oraclePrice();
        uint256 expectedOraclePrice = _calculateDelta(
            oraclePrice,
            monthlyChangeRateBasisPoints + Constants.BASIS_POINTS_GRANULARITY
        );
        uint256 previousStartTime = voltSystemOracle.periodStartTime();
        assertEq(voltSystemOracle.getCurrentOraclePrice(), expectedOraclePrice);

        voltSystemOracle.compoundInterest();

        assertEq(voltSystemOracle.oraclePrice(), expectedOraclePrice);
        assertEq(
            previousStartTime + voltSystemOracle.TIMEFRAME(),
            voltSystemOracle.periodStartTime()
        );
    }

    function testLinearInterpolation() public {
        vm.warp(
            voltSystemOracle.periodStartTime() + voltSystemOracle.TIMEFRAME()
        );
        uint256 periodOneEndPrice = 1065997259354468954;

        assertEq(
            voltSystemOracle.getCurrentOraclePrice(),
            periodOneEndPrice /// oracle value after 1 period at 2% increase
        );

        uint256 previousStartTime = voltSystemOracle.periodStartTime();
        voltSystemOracle.compoundInterest();
        vm.warp(block.timestamp + voltSystemOracle.TIMEFRAME());

        assertEq(periodOneEndPrice, voltSystemOracle.oraclePrice());
        assertEq(
            previousStartTime + voltSystemOracle.TIMEFRAME(),
            voltSystemOracle.periodStartTime()
        );
        assertEq(
            voltSystemOracle.getCurrentOraclePrice(),
            1087317204541558333 /// oracle value after 2 periods at 2% increase, compounded annually
        );
    }

    /// assert that price cannot increase before block.timestamp of 100,000
    /// since uint16 max is 65,535, the current oracle price cannot increase
    function testNoLinearInterpolationBeforeStartTime(uint16 x) public {
        vm.warp(block.timestamp + x);

        assertEq(
            voltSystemOracle.getCurrentOraclePrice(),
            voltSystemOracle.oraclePrice()
        );
    }

    /// sequentially compound interest after multiple missed compounding events
    function testMultipleSequentialPeriodCompounds() public {
        /// anything over this amount of periods gets the oracle price into
        /// a zone where it could overflow during call to getCurrentOraclePrice
        uint16 periods = 6192;
        vm.warp(
            voltSystemOracle.periodStartTime() +
                (periods * voltSystemOracle.TIMEFRAME())
        );

        uint256 expectedOraclePrice = voltSystemOracle.oraclePrice();

        for (uint256 i = 0; i < periods; i++) {
            uint256 previousStartTime = voltSystemOracle.periodStartTime();
            voltSystemOracle.compoundInterest(); /// compound interest periods amount of times
            expectedOraclePrice = _calculateDelta(
                expectedOraclePrice,
                voltSystemOracle.monthlyChangeRateBasisPoints() +
                    Constants.BASIS_POINTS_GRANULARITY
            );
            assertEq(expectedOraclePrice, voltSystemOracle.oraclePrice());
            assertEq(
                previousStartTime + voltSystemOracle.TIMEFRAME(),
                voltSystemOracle.periodStartTime()
            );
        }
    }

    function testLinearInterpolationFuzz(uint32 timeIncrease) public {
        vm.warp(
            block.timestamp + voltSystemOracle.periodStartTime() + timeIncrease
        );
        uint256 cachedOraclePrice = voltSystemOracle.oraclePrice();

        if (timeIncrease >= voltSystemOracle.TIMEFRAME()) {
            assertEq(
                voltSystemOracle.getCurrentOraclePrice(),
                _calculateDelta(
                    cachedOraclePrice,
                    monthlyChangeRateBasisPoints +
                        Constants.BASIS_POINTS_GRANULARITY
                )
            );
        } else {
            uint256 timeDelta = block.timestamp -
                voltSystemOracle.periodStartTime();
            uint256 pricePercentageChange = _calculateDelta(
                cachedOraclePrice,
                voltSystemOracle.monthlyChangeRateBasisPoints()
            );
            uint256 priceDelta = (pricePercentageChange * timeDelta) /
                voltSystemOracle.TIMEFRAME();
            assertEq(
                voltSystemOracle.getCurrentOraclePrice(),
                priceDelta + cachedOraclePrice
            );
            uint256 endingOraclePrice = _calculateDelta(
                cachedOraclePrice,
                monthlyChangeRateBasisPoints +
                    Constants.BASIS_POINTS_GRANULARITY
            );
            uint256 periodStartTime = voltSystemOracle.periodStartTime();
            uint256 duration = voltSystemOracle.TIMEFRAME();
            uint256 expectedOraclePrice = _calculateLinearInterpolation(
                Math.min(block.timestamp, periodStartTime + duration), /// calculate interest accrued at this point in time
                periodStartTime, /// x1
                periodStartTime + voltSystemOracle.TIMEFRAME(), /// x2
                cachedOraclePrice, /// y1
                endingOraclePrice /// y2
            );
            assertEq(
                voltSystemOracle.getCurrentOraclePrice(),
                expectedOraclePrice
            );
            assertEq(priceDelta + cachedOraclePrice, expectedOraclePrice);
        }
    }

    function testLinearInterpolationFuzzMultiplePeriods(
        uint32 timeIncrease,
        uint8 periods
    ) public {
        /// get past start time so that interest can start accruing
        vm.warp(block.timestamp + voltSystemOracle.periodStartTime());

        for (uint256 i = 0; i < periods; i++) {
            vm.warp(block.timestamp + timeIncrease);

            uint256 cachedOraclePrice = voltSystemOracle.oraclePrice();

            /// ensure interest accrues properly before compounding
            if (timeIncrease >= voltSystemOracle.TIMEFRAME()) {
                assertEq(
                    voltSystemOracle.getCurrentOraclePrice(),
                    _calculateDelta(
                        cachedOraclePrice,
                        monthlyChangeRateBasisPoints +
                            Constants.BASIS_POINTS_GRANULARITY
                    )
                );
            } else {
                uint256 timeDelta = Math.min(
                    block.timestamp - voltSystemOracle.periodStartTime(),
                    voltSystemOracle.TIMEFRAME()
                );
                uint256 pricePercentageChange = _calculateDelta(
                    cachedOraclePrice,
                    voltSystemOracle.monthlyChangeRateBasisPoints()
                );
                uint256 priceDelta = (pricePercentageChange * timeDelta) /
                    voltSystemOracle.TIMEFRAME();
                assertEq(
                    voltSystemOracle.getCurrentOraclePrice(),
                    priceDelta + cachedOraclePrice
                );
                uint256 endingOraclePrice = _calculateDelta(
                    cachedOraclePrice,
                    monthlyChangeRateBasisPoints +
                        Constants.BASIS_POINTS_GRANULARITY
                );
                uint256 periodStartTime = voltSystemOracle.periodStartTime();
                uint256 duration = voltSystemOracle.TIMEFRAME();
                uint256 expectedOraclePrice = _calculateLinearInterpolation(
                    Math.min(block.timestamp, periodStartTime + duration), /// calculate interest accrued at this point in time
                    periodStartTime, /// x1
                    periodStartTime + voltSystemOracle.TIMEFRAME(), /// x2
                    cachedOraclePrice, /// y1
                    endingOraclePrice /// y2
                );
                assertEq(
                    voltSystemOracle.getCurrentOraclePrice(),
                    expectedOraclePrice
                );
                assertEq(priceDelta + cachedOraclePrice, expectedOraclePrice);
            }

            bool isTimeEnded = block.timestamp >=
                voltSystemOracle.periodStartTime() +
                    voltSystemOracle.TIMEFRAME();

            if (isTimeEnded) {
                uint256 currentPeriodStart = voltSystemOracle.periodStartTime();
                voltSystemOracle.compoundInterest();
                assertEq(
                    currentPeriodStart + voltSystemOracle.TIMEFRAME(),
                    voltSystemOracle.periodStartTime()
                );

                /// ensure accumulator updates correctly on interest compounding
                assertEq(
                    voltSystemOracle.oraclePrice(),
                    _calculateDelta(
                        cachedOraclePrice,
                        monthlyChangeRateBasisPoints +
                            Constants.BASIS_POINTS_GRANULARITY
                    )
                );
            }
        }
    }

    function testLinearInterpolationUnderYearFuzzPeriods(
        uint24 timeIncrease, /// bound input to 16,777,215 which is lt 31,536,000 (seconds per year)
        uint8 periods
    ) public {
        /// get past start time so that interest can start accruing
        vm.warp(block.timestamp + voltSystemOracle.periodStartTime());

        for (uint256 i = 0; i < periods; i++) {
            vm.warp(block.timestamp + timeIncrease);

            uint256 cachedOraclePrice = voltSystemOracle.oraclePrice();
            uint256 duration = voltSystemOracle.TIMEFRAME();
            uint256 endingOraclePrice = _calculateDelta(
                cachedOraclePrice,
                monthlyChangeRateBasisPoints +
                    Constants.BASIS_POINTS_GRANULARITY
            );
            uint256 periodStartTime = voltSystemOracle.periodStartTime();
            /// double check contract's math and use LERP to verify both algorithms generate the same price at t
            uint256 expectedOraclePrice = _calculateLinearInterpolation(
                Math.min(block.timestamp, periodStartTime + duration), /// calculate interest accrued at this point in time
                periodStartTime, /// x1
                periodStartTime + duration, /// x2
                cachedOraclePrice, /// y1
                endingOraclePrice /// y2
            );

            uint256 timeDelta = Math.min(
                block.timestamp - periodStartTime,
                duration
            );
            uint256 priceChangeOverPeriod = endingOraclePrice -
                cachedOraclePrice;
            uint256 priceDelta = (priceChangeOverPeriod * timeDelta) /
                voltSystemOracle.TIMEFRAME();

            assertEq(
                voltSystemOracle.getCurrentOraclePrice(),
                priceDelta + cachedOraclePrice
            );
            assertEq(priceDelta + cachedOraclePrice, expectedOraclePrice);

            bool isTimeEnded = block.timestamp >=
                voltSystemOracle.periodStartTime() + duration;

            if (isTimeEnded) {
                voltSystemOracle.compoundInterest();
                assertEq(
                    periodStartTime + voltSystemOracle.TIMEFRAME(),
                    voltSystemOracle.periodStartTime()
                );

                /// ensure accumulator updates correctly on interest compounding
                assertEq(
                    voltSystemOracle.oraclePrice(),
                    _calculateDelta(
                        cachedOraclePrice,
                        monthlyChangeRateBasisPoints +
                            Constants.BASIS_POINTS_GRANULARITY
                    )
                );
            }
        }
    }

    /// Linear Interpolation Formula
    /// (y) = y1 + (x − x1) * ((y2 − y1) / (x2 − x1))
    /// @notice calculate linear interpolation and return ending price
    /// @param x is time value to calculate interpolation on
    /// @param x1 is starting time to calculate interpolation from
    /// @param x2 is ending time to calculate interpolation to
    /// @param y1 is starting price to calculate interpolation from
    /// @param y2 is ending price to calculate interpolation to
    function _calculateLinearInterpolation(
        uint256 x,
        uint256 x1,
        uint256 x2,
        uint256 y1,
        uint256 y2
    ) internal pure returns (uint256 y) {
        uint256 firstDeltaX = x - x1; /// will not overflow because x should always be gte x1
        uint256 secondDeltaX = x2 - x1; /// will not overflow because x2 should always be gt x1
        uint256 deltaY = y2 - y1; /// will not overflow because y2 should always be gt y1

        uint256 product = (firstDeltaX * deltaY) / secondDeltaX;
        y = product + y1;
    }

    function _calculateDelta(
        uint256 oldOraclePrice,
        uint256 changeRateBasisPoints
    ) internal pure returns (uint256) {
        uint256 basisPoints = Constants.BASIS_POINTS_GRANULARITY;
        return (oldOraclePrice * changeRateBasisPoints) / basisPoints;
    }
}
