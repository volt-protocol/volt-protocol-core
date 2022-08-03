// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Vm} from "./../unit/utils/Vm.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {getCore, getAddresses, VoltTestAddresses} from "./../unit/utils/Fixtures.sol";
import {MockScalingPriceOracle} from "../../mock/MockScalingPriceOracle.sol";
import {MockL2ScalingPriceOracle} from "../../mock/MockL2ScalingPriceOracle.sol";
import {MockChainlinkToken} from "../../mock/MockChainlinkToken.sol";
import {Decimal} from "./../../external/Decimal.sol";
import {ScalingPriceOracle} from "./../../oracle/ScalingPriceOracle.sol";
import {L2ScalingPriceOracle} from "./../../oracle/L2ScalingPriceOracle.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";

contract IntegrationTestL2ScalingPriceOracle is DSTest {
    using Decimal for Decimal.D256;
    using SafeCast for *;

    ScalingPriceOracle private scalingPriceOracle =
        ScalingPriceOracle(0x79412660E95F94a4D2d02a050CEA776200939917);
    L2ScalingPriceOracle private l2scalingPriceOracle;

    /// @notice address of chainlink token on arbitrum
    address public constant chainlinkToken =
        0xf97f4df75117a78c1A5a0DBb814Af92458539FB4;

    /// @notice increase price by x% per month
    int256 public monthlyChangeRateBasisPoints =
        scalingPriceOracle.monthlyChangeRateBasisPoints();

    /// @notice the current month's CPI data from ScalingPriceOracle
    uint128 public currentMonth = scalingPriceOracle.currentMonth();

    /// @notice the previous month's CPI data from ScalingPriceOracle
    uint128 public previousMonth = scalingPriceOracle.previousMonth();

    /// @notice address of chainlink oracle to send request
    address public oracle = scalingPriceOracle.oracle();

    /// @notice job id that retrieves the latest CPI data
    bytes32 public jobId = scalingPriceOracle.jobId();

    /// @notice fee of 10 link
    uint256 public fee = scalingPriceOracle.fee();

    /// @notice starting time of the current mainnet scaling price oracle
    uint256 public startTime = scalingPriceOracle.startTime();

    /// @notice starting price of the current mainnet scaling price oracle
    uint256 public startOraclePrice = scalingPriceOracle.oraclePrice();

    Vm public constant vm = Vm(HEVM_ADDRESS);

    VoltTestAddresses public addresses = getAddresses();

    function setUp() public {
        l2scalingPriceOracle = new L2ScalingPriceOracle(
            oracle,
            jobId,
            fee,
            currentMonth,
            previousMonth,
            chainlinkToken,
            startTime,
            startOraclePrice
        );
    }

    function testSetup() public {
        assertEq(
            scalingPriceOracle.remainingTime(),
            l2scalingPriceOracle.remainingTime()
        );
        assertTrue(
            scalingPriceOracle.isTimeEnded() ==
                l2scalingPriceOracle.isTimeEnded()
        );
        assertEq(
            scalingPriceOracle.startTime(),
            l2scalingPriceOracle.startTime()
        );
        assertEq(
            scalingPriceOracle.oraclePrice(),
            l2scalingPriceOracle.oraclePrice()
        ); /// starting price is correct
        assertEq(scalingPriceOracle.oracle(), l2scalingPriceOracle.oracle());
        assertEq(scalingPriceOracle.jobId(), l2scalingPriceOracle.jobId());
        assertEq(scalingPriceOracle.fee(), l2scalingPriceOracle.fee());
        assertEq(
            scalingPriceOracle.currentMonth(),
            l2scalingPriceOracle.currentMonth()
        );
        assertEq(
            scalingPriceOracle.previousMonth(),
            l2scalingPriceOracle.previousMonth()
        );
        assertEq(
            scalingPriceOracle.getMonthlyAPR(),
            l2scalingPriceOracle.getMonthlyAPR()
        );
        assertEq(
            scalingPriceOracle.getCurrentOraclePrice(),
            l2scalingPriceOracle.getCurrentOraclePrice()
        );
        assertEq(
            l2scalingPriceOracle.getChainlinkTokenAddress(),
            chainlinkToken
        );
    }

    function _testOraclePriceEquivalence() internal {
        assertEq(
            scalingPriceOracle.getCurrentOraclePrice(),
            l2scalingPriceOracle.getCurrentOraclePrice()
        );
        assertEq(
            scalingPriceOracle.oraclePrice(),
            l2scalingPriceOracle.oraclePrice()
        );
    }

    /// positive price action from oracle -- inflation case
    function testGetCurrentOraclePriceAfterInterpolation() public {
        vm.warp(block.timestamp + 28 days);
        _testOraclePriceEquivalence();
    }

    /// negative price action from oracle -- deflation case
    function testPriceDecreaseAfterInterpolation() public {
        scalingPriceOracle = new MockScalingPriceOracle(
            oracle,
            jobId,
            fee,
            previousMonth, /// flip current and previous months so that rate is -3%
            currentMonth,
            chainlinkToken
        );

        l2scalingPriceOracle = new MockL2ScalingPriceOracle(
            oracle,
            jobId,
            fee,
            previousMonth, /// flip current and previous months so that rate is -3%
            currentMonth,
            chainlinkToken,
            scalingPriceOracle.startTime(),
            1e18
        );

        vm.warp(block.timestamp + 29 days);
        assertEq(
            l2scalingPriceOracle.getCurrentOraclePrice(),
            scalingPriceOracle.getCurrentOraclePrice()
        );

        assertEq(
            l2scalingPriceOracle.oraclePrice().toInt256() +
                (l2scalingPriceOracle.monthlyChangeRateBasisPoints() * 1e18) /
                10_000,
            l2scalingPriceOracle.getCurrentOraclePrice().toInt256()
        );
        assertEq(
            scalingPriceOracle.oraclePrice().toInt256() +
                (scalingPriceOracle.monthlyChangeRateBasisPoints() * 1e18) /
                10_000,
            scalingPriceOracle.getCurrentOraclePrice().toInt256()
        );
        assertEq(l2scalingPriceOracle.remainingTime(), 0);
        assertEq(scalingPriceOracle.remainingTime(), 0);

        _testOraclePriceEquivalence();
    }

    function testFulfillFailureTimed() public {
        if (scalingPriceOracle.isTimeEnded()) {
            vm.warp(scalingPriceOracle.startTime()); /// warp to start time if time has ended
        }

        assertTrue(!scalingPriceOracle.isTimeEnded());
        assertTrue(!l2scalingPriceOracle.isTimeEnded());

        vm.expectRevert(bytes("Timed: time not ended, init"));
        l2scalingPriceOracle.requestCPIData();

        vm.expectRevert(bytes("Timed: time not ended, init"));
        scalingPriceOracle.requestCPIData();
    }
}
