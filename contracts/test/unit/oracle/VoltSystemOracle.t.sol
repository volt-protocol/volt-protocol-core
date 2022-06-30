// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Vm} from "./../utils/Vm.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {getCore, getAddresses, VoltTestAddresses} from "./../utils/Fixtures.sol";
import {MockScalingPriceOracle} from "../../../mock/MockScalingPriceOracle.sol";
import {VoltSystemOracle} from "../../../oracle/VoltSystemOracle.sol";
import {ScalingPriceOracle} from "../../../oracle/ScalingPriceOracle.sol";
import {MockChainlinkToken} from "../../../mock/MockChainlinkToken.sol";
import {Decimal} from "./../../../external/Decimal.sol";
import {Constants} from "./../../../Constants.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract VoltSystemOracleTest is DSTest {
    using Decimal for Decimal.D256;
    using SafeCast for *;

    /// @notice reference to the volt system oracle
    VoltSystemOracle private voltSystemOracle;

    /// @notice increase the volt target price by 2% annually
    uint256 public constant annualChangeRateBasisPoints = 200;

    /// @notice block time at which the VSO (Volt System Oracle) will start accruing interest
    uint256 public constant startTime = 100_000;

    /// @notice starting oracle price
    uint256 public constant startPrice = 1.0387e18;

    Vm public constant vm = Vm(HEVM_ADDRESS);
    VoltTestAddresses public addresses = getAddresses();

    function setUp() public {
        voltSystemOracle = new VoltSystemOracle(
            annualChangeRateBasisPoints,
            startTime,
            startPrice
        );
    }

    /// sequentially compound interest after multiple missed compounding events
    function testMultipleSequentialPeriodCompounds(uint8 periods) public {
        /// anything over this amount of periods gets the oracle price into
        /// a zone where it could overflow during call to getCurrentOraclePrice
        vm.assume(periods < 6193);
        vm.warp(
            voltSystemOracle.periodStartTime() +
                (periods * voltSystemOracle.TIMEFRAME())
        );

        uint256 expectedOraclePrice = voltSystemOracle.oraclePrice();

        for (uint256 i = 0; i < periods; i++) {
            voltSystemOracle.compoundInterest(); /// compound interest periods amount of times
            expectedOraclePrice = _calculateDelta(
                expectedOraclePrice,
                voltSystemOracle.annualChangeRateBasisPoints() +
                    Constants.BASIS_POINTS_GRANULARITY
            );
            assertEq(expectedOraclePrice, voltSystemOracle.oraclePrice());
        }
    }

    function testSetup() public {
        assertEq(voltSystemOracle.oraclePrice(), startPrice);
        assertEq(
            voltSystemOracle.annualChangeRateBasisPoints(),
            annualChangeRateBasisPoints
        );
        assertEq(voltSystemOracle.periodStartTime(), startTime);
        assertEq(voltSystemOracle.getCurrentOraclePrice(), startPrice);
    }

    function testCompoundBeforePeriodStartFails() public {
        vm.expectRevert("VoltSystemOracle: not past end time");
        voltSystemOracle.compoundInterest();
    }

    function testCompoundSucceedsAfterOneYear() public {
        assertEq(voltSystemOracle.oraclePrice(), startPrice);
        vm.warp(block.timestamp + voltSystemOracle.periodStartTime());

        uint256 oraclePrice = voltSystemOracle.oraclePrice();

        vm.warp(block.timestamp + 365 days);

        uint256 expectedOraclePrice = _calculateDelta(
            oraclePrice,
            annualChangeRateBasisPoints + Constants.BASIS_POINTS_GRANULARITY
        );
        assertEq(voltSystemOracle.getCurrentOraclePrice(), expectedOraclePrice);
        voltSystemOracle.compoundInterest();
        assertEq(voltSystemOracle.oraclePrice(), expectedOraclePrice);
    }

    function testLinearInterpolation() public {
        assertEq(voltSystemOracle.oraclePrice(), startPrice);
        vm.warp(voltSystemOracle.periodStartTime() + 365 days);

        assertEq(
            voltSystemOracle.getCurrentOraclePrice(),
            _calculateDelta(
                startPrice,
                annualChangeRateBasisPoints + Constants.BASIS_POINTS_GRANULARITY
            )
        );
    }

    /// assert that price cannot increase before block.timestamp of 100,000
    /// since uint16 max is 65,535, the current oracle price cannot increase
    function testNoLinearInterpolationBeforeStartTime(uint16 x) public {
        assertEq(voltSystemOracle.oraclePrice(), startPrice);
        vm.warp(block.timestamp + x);

        assertEq(
            voltSystemOracle.getCurrentOraclePrice(),
            voltSystemOracle.oraclePrice()
        );
    }

    function testLinearInterpolationOnlyAfterStartTime(uint16 x) public {
        assertEq(voltSystemOracle.oraclePrice(), startPrice);
        vm.warp(block.timestamp + x);
        uint256 cachedOraclePrice = voltSystemOracle.oraclePrice();

        if (x > voltSystemOracle.periodStartTime()) {
            /// interpolation because past start time
            uint256 timeDelta = block.timestamp -
                voltSystemOracle.periodStartTime();
            uint256 pricePercentageChange = _calculateDelta(
                cachedOraclePrice,
                voltSystemOracle.annualChangeRateBasisPoints()
            );
            uint256 priceDelta = (pricePercentageChange * timeDelta) / 365 days;
            assertEq(
                voltSystemOracle.getCurrentOraclePrice(),
                priceDelta + cachedOraclePrice
            );
        } else {
            /// no interpolation because not past start time
            assertEq(
                voltSystemOracle.getCurrentOraclePrice(),
                cachedOraclePrice
            );
        }
    }

    function testLinearInterpolationFuzz(uint32 timeIncrease) public {
        vm.warp(block.timestamp + voltSystemOracle.periodStartTime());
        uint256 cachedOraclePrice = voltSystemOracle.oraclePrice();

        vm.warp(block.timestamp + timeIncrease);

        if (timeIncrease >= 365 days) {
            assertEq(
                voltSystemOracle.getCurrentOraclePrice(),
                _calculateDelta(
                    cachedOraclePrice,
                    annualChangeRateBasisPoints +
                        Constants.BASIS_POINTS_GRANULARITY
                )
            );
        } else {
            uint256 timeDelta = block.timestamp -
                voltSystemOracle.periodStartTime();
            uint256 pricePercentageChange = _calculateDelta(
                cachedOraclePrice,
                voltSystemOracle.annualChangeRateBasisPoints()
            );
            uint256 priceDelta = (pricePercentageChange * timeDelta) / 365 days;
            assertEq(
                voltSystemOracle.getCurrentOraclePrice(),
                priceDelta + cachedOraclePrice
            );
        }
    }

    function testLinearInterpolationFuzzCycles(
        uint32 timeIncrease,
        uint8 cycles
    ) public {
        /// get past start time so that interest can start accruing
        vm.warp(block.timestamp + voltSystemOracle.periodStartTime());

        for (uint256 i = 0; i < cycles; i++) {
            vm.warp(block.timestamp + timeIncrease);

            uint256 cachedOraclePrice = voltSystemOracle.oraclePrice();

            /// ensure interest accrues properly before compounding
            if (timeIncrease >= 365 days) {
                assertEq(
                    voltSystemOracle.getCurrentOraclePrice(),
                    _calculateDelta(
                        cachedOraclePrice,
                        annualChangeRateBasisPoints +
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
                    voltSystemOracle.annualChangeRateBasisPoints()
                );
                uint256 priceDelta = (pricePercentageChange * timeDelta) /
                    365 days;
                assertEq(
                    voltSystemOracle.getCurrentOraclePrice(),
                    priceDelta + cachedOraclePrice
                );
            }

            bool isTimeEnded = block.timestamp >=
                voltSystemOracle.periodStartTime() +
                    voltSystemOracle.TIMEFRAME();

            if (isTimeEnded) {
                voltSystemOracle.compoundInterest();
                /// ensure accumulator updates correctly on interest compounding
                assertEq(
                    voltSystemOracle.oraclePrice(),
                    _calculateDelta(
                        cachedOraclePrice,
                        annualChangeRateBasisPoints +
                            Constants.BASIS_POINTS_GRANULARITY
                    )
                );
            }
        }
    }

    function testLinearInterpolationUnderYearFuzzCycles(
        uint24 timeIncrease, /// bound input to 16,777,215 which is lt 31,536,000
        uint8 cycles
    ) public {
        /// get past start time so that interest can start accruing
        vm.warp(block.timestamp + voltSystemOracle.periodStartTime());

        for (uint256 i = 0; i < cycles; i++) {
            vm.warp(block.timestamp + timeIncrease);

            uint256 cachedOraclePrice = voltSystemOracle.oraclePrice();

            uint256 timeDelta = Math.min(
                block.timestamp - voltSystemOracle.periodStartTime(),
                voltSystemOracle.TIMEFRAME()
            );
            uint256 pricePercentageChange = _calculateDelta(
                cachedOraclePrice,
                voltSystemOracle.annualChangeRateBasisPoints()
            );
            uint256 priceDelta = (pricePercentageChange * timeDelta) / 365 days;
            assertEq(
                voltSystemOracle.getCurrentOraclePrice(),
                priceDelta + cachedOraclePrice
            );

            bool isTimeEnded = block.timestamp >=
                voltSystemOracle.periodStartTime() +
                    voltSystemOracle.TIMEFRAME();

            if (isTimeEnded) {
                voltSystemOracle.compoundInterest();
                /// ensure accumulator updates correctly on interest compounding
                assertEq(
                    voltSystemOracle.oraclePrice(),
                    _calculateDelta(
                        cachedOraclePrice,
                        annualChangeRateBasisPoints +
                            Constants.BASIS_POINTS_GRANULARITY
                    )
                );
            }
        }
    }

    function _calculateDelta(
        uint256 oldOraclePrice,
        uint256 changeRateBasisPoints
    ) internal pure returns (uint256) {
        uint256 basisPoints = Constants.BASIS_POINTS_GRANULARITY;
        return (oldOraclePrice * changeRateBasisPoints) / basisPoints;
    }
}
