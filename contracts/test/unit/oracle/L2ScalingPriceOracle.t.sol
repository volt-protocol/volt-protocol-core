// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Vm} from "./../utils/Vm.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {getCore, getAddresses, FeiTestAddresses} from "./../utils/Fixtures.sol";
import {MockScalingPriceOracle} from "../../../mock/MockScalingPriceOracle.sol";
import {MockL2ScalingPriceOracle} from "../../../mock/MockL2ScalingPriceOracle.sol";
import {MockChainlinkToken} from "../../../mock/MockChainlinkToken.sol";
import {Decimal} from "./../../../external/Decimal.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";

contract L2ScalingPriceOracleTest is DSTest {
    using Decimal for Decimal.D256;
    using SafeCast for *;

    MockScalingPriceOracle private scalingPriceOracle;
    MockL2ScalingPriceOracle private l2scalingPriceOracle;

    /// @notice increase price by 3.09% per month
    int256 public constant monthlyChangeRateBasisPoints = 309;

    /// @notice the current month's CPI data
    uint128 public constant currentMonth = 270000;

    /// @notice the previous month's CPI data
    uint128 public constant previousMonth = 261900;

    /// @notice address of chainlink oracle to send request
    address public immutable oracle = address(0);

    /// @notice job id that retrieves the latest CPI data
    bytes32 public immutable jobId =
        keccak256(abi.encodePacked("Chainlink CPI-U job"));

    /// @notice fee of 10 link
    uint256 public immutable fee = 1e19;

    Vm public constant vm = Vm(HEVM_ADDRESS);
    FeiTestAddresses public addresses = getAddresses();

    uint256 public constant startTime = 50 days;

    function setUp() public {
        /// set this code at address 0 so _rawRequest in ChainlinkClient succeeds
        MockChainlinkToken token = new MockChainlinkToken();
        vm.etch(address(0), address(token).code);

        /// warp to 50 days to set isTimeStarted to true and pass deployment check
        vm.warp(startTime);

        scalingPriceOracle = new MockScalingPriceOracle(
            oracle,
            jobId,
            fee,
            currentMonth,
            previousMonth
        );

        vm.warp(block.timestamp + 20 days); /// now 70 days have passed

        l2scalingPriceOracle = new MockL2ScalingPriceOracle(
            oracle,
            jobId,
            fee,
            currentMonth,
            previousMonth,
            50 days,
            1e18
        );
    }

    function testSetup() public {
        assertEq(l2scalingPriceOracle.remainingTime(), 8 days);
        assertEq(scalingPriceOracle.remainingTime(), 8 days);
        assertTrue(!l2scalingPriceOracle.isTimeEnded());
        assertEq(l2scalingPriceOracle.startTime(), startTime);
        assertEq(l2scalingPriceOracle.oraclePrice(), 1e18); /// starting price is correct
        assertEq(scalingPriceOracle.oracle(), oracle);
        assertEq(scalingPriceOracle.jobId(), jobId);
        assertEq(scalingPriceOracle.fee(), fee);
        assertEq(scalingPriceOracle.currentMonth(), currentMonth);
        assertEq(scalingPriceOracle.previousMonth(), previousMonth);
        assertEq(
            scalingPriceOracle.getMonthlyAPR(),
            monthlyChangeRateBasisPoints
        );
    }

    function testOracleSetupEquivalence() public {
        assertEq(
            scalingPriceOracle.getCurrentOraclePrice(),
            l2scalingPriceOracle.getCurrentOraclePrice()
        );
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
    function testReadGetCurrentOraclePriceAfterInterpolation() public {
        vm.warp(block.timestamp + 28 days);
        assertEq(10309e14, scalingPriceOracle.getCurrentOraclePrice());
        _testOraclePriceEquivalence();
    }

    /// negative price action from oracle -- deflation case
    function testPriceDecreaseAfterInterpolation() public {
        scalingPriceOracle = new MockScalingPriceOracle(
            oracle,
            jobId,
            fee,
            previousMonth, /// flip current and previous months so that rate is -3%
            currentMonth
        );
        l2scalingPriceOracle = new MockL2ScalingPriceOracle(
            oracle,
            jobId,
            fee,
            previousMonth, /// flip current and previous months so that rate is -3%
            currentMonth,
            block.timestamp,
            1e18
        );

        vm.warp(block.timestamp + 28 days);
        assertEq(97e16, scalingPriceOracle.getCurrentOraclePrice());
        assertEq(97e16, l2scalingPriceOracle.getCurrentOraclePrice());
        assertEq(l2scalingPriceOracle.remainingTime(), 0);
        assertEq(scalingPriceOracle.remainingTime(), 0);

        _testOraclePriceEquivalence();
    }

    function testFulfillFailureTimed() public {
        assertTrue(!scalingPriceOracle.isTimeEnded());
        assertTrue(!l2scalingPriceOracle.isTimeEnded());

        vm.expectRevert(bytes("Timed: time not ended, init"));

        l2scalingPriceOracle.requestCPIData();
    }

    function testFulfillMaxDeviationExceededFailureUp() public {
        vm.expectRevert(
            bytes(
                "ScalingPriceOracle: Chainlink data outside of deviation threshold"
            )
        );

        /// this will fail as it is 21% inflation and max allowable is 20%
        l2scalingPriceOracle.fulfill((currentMonth * 121) / 100);
    }

    function testFulfillFailsWhenNotChainlinkOracle() public {
        vm.warp(block.timestamp + 45 days);
        bytes32 requestId = scalingPriceOracle.requestCPIData();
        vm.expectRevert(bytes("Source must be the oracle of the request"));

        l2scalingPriceOracle.fulfill(requestId, currentMonth);
    }

    function testFulfillMaxDeviationExceededFailureDown() public {
        vm.expectRevert(
            bytes(
                "ScalingPriceOracle: Chainlink data outside of deviation threshold"
            )
        );

        /// this will fail as it is 21% inflation and max allowable is 20%
        l2scalingPriceOracle.fulfill((currentMonth * 79) / 100);
    }

    function testRequestSucceeds() public {
        vm.warp(block.timestamp + 45 days);
        uint256 oraclePrice = scalingPriceOracle.getCurrentOraclePrice();

        assertEq(l2scalingPriceOracle.remainingTime(), 0);
        assertEq(scalingPriceOracle.remainingTime(), 0);

        /// this will succeed and compound interest
        scalingPriceOracle.requestCPIData();
        l2scalingPriceOracle.requestCPIData();

        uint256 storedPrice = scalingPriceOracle.oraclePrice();
        uint256 l2StoredPrice = l2scalingPriceOracle.oraclePrice();

        assertEq(oraclePrice, storedPrice);
        assertEq(oraclePrice, l2StoredPrice);

        _testOraclePriceEquivalence();
    }

    function testFulfillSucceedsTwentyPercent() public {
        uint256 storedCurrentMonth = l2scalingPriceOracle.currentMonth();
        uint256 newCurrentMonth = (currentMonth * 120) / 100;

        /// this will succeed as max allowable is 20%
        l2scalingPriceOracle.fulfill(newCurrentMonth);
        scalingPriceOracle.fulfill(newCurrentMonth);

        assertEq(l2scalingPriceOracle.monthlyChangeRateBasisPoints(), 2_000);
        /// assert that all state transitions were done correctly with current and previous month
        assertEq(l2scalingPriceOracle.previousMonth(), storedCurrentMonth);
        assertEq(l2scalingPriceOracle.currentMonth(), newCurrentMonth);
        _testOraclePriceEquivalence();
    }

    function testFulfillSucceedsTwentyPercentTwoMonths() public {
        vm.warp(block.timestamp + 33 days);
        uint256 storedCurrentMonth = l2scalingPriceOracle.currentMonth();
        uint256 newCurrentMonth = (currentMonth * 120) / 100;

        /// this will succeed as max allowable is 20%
        l2scalingPriceOracle.fulfill(newCurrentMonth);

        assertEq(l2scalingPriceOracle.monthlyChangeRateBasisPoints(), 2_000);
        /// assert that all state transitions were done correctly with current and previous month
        assertEq(l2scalingPriceOracle.previousMonth(), storedCurrentMonth);
        assertEq(l2scalingPriceOracle.currentMonth(), newCurrentMonth);

        vm.warp(block.timestamp + 31 days);
        newCurrentMonth = (newCurrentMonth * 120) / 100;

        bytes32 requestId = l2scalingPriceOracle.requestCPIData();
        vm.prank(address(0));
        /// this will succeed as max allowable is 20%
        l2scalingPriceOracle.fulfill(requestId, newCurrentMonth);
        assertEq(l2scalingPriceOracle.oraclePrice(), 1.2e18);

        vm.warp(block.timestamp + 31 days);
        assertEq(
            l2scalingPriceOracle.getCurrentOraclePrice(),
            (1.2e18 * 120) / 100
        );

        requestId = l2scalingPriceOracle.requestCPIData();
        vm.prank(address(0));
        l2scalingPriceOracle.fulfill(requestId, newCurrentMonth);
        assertEq(l2scalingPriceOracle.oraclePrice(), (1.2e18 * 120) / 100);
    }

    function testFulfillSucceedsTwentyPercentTwelveMonths() public {
        vm.warp(block.timestamp + 33 days);
        uint256 newCurrentMonth = (currentMonth * 120) / 100;
        uint256 price = l2scalingPriceOracle.getCurrentOraclePrice();

        for (uint256 i = 0; i < 12; i++) {
            uint256 storedCurrentMonth = l2scalingPriceOracle.currentMonth();

            vm.warp(block.timestamp + 31 days);
            bytes32 requestId = l2scalingPriceOracle.requestCPIData();
            /// prank to allow request to be fulfilled
            vm.prank(address(0));
            /// this will succeed as max allowable is 20%
            l2scalingPriceOracle.fulfill(requestId, newCurrentMonth);
            assertEq(l2scalingPriceOracle.getCurrentOraclePrice(), price);

            uint256 expectedChangeRateBasisPoints = ((l2scalingPriceOracle
                .currentMonth() - l2scalingPriceOracle.previousMonth()) *
                10_000) / l2scalingPriceOracle.previousMonth();

            assertEq(
                l2scalingPriceOracle.monthlyChangeRateBasisPoints(),
                expectedChangeRateBasisPoints.toInt256()
            );
            assertEq(l2scalingPriceOracle.previousMonth(), storedCurrentMonth);
            assertEq(l2scalingPriceOracle.currentMonth(), newCurrentMonth);

            assertEq(l2scalingPriceOracle.oraclePrice(), price);

            newCurrentMonth =
                (newCurrentMonth * (10_000 + expectedChangeRateBasisPoints)) /
                10_000;
            price = (price * (10_000 + expectedChangeRateBasisPoints)) / 10_000;
        }
    }

    function testFulfillFailureCalendar() public {
        vm.warp(block.timestamp + 32 days);

        vm.expectRevert(
            bytes("ScalingPriceOracle: cannot request data before the 15th")
        );

        l2scalingPriceOracle.requestCPIData();
    }

    function testDeploymentFailsWithIncorrectStartTime() public {
        vm.warp(28 days); /// this will mean delta between block.timestamp and timeframe is 0
        vm.expectRevert(
            bytes("L2ScalingPriceOracle: Start time too far in the past")
        );
        l2scalingPriceOracle = new MockL2ScalingPriceOracle(
            oracle,
            jobId,
            fee,
            currentMonth,
            previousMonth,
            0, /// cause first check to fail as 0 < 1
            1e18
        );
    }

    function testDeploymentFailsWithIncorrectStartingOraclePrice() public {
        vm.expectRevert(
            bytes("L2ScalingPriceOracle: Starting oracle price too low")
        );
        l2scalingPriceOracle = new MockL2ScalingPriceOracle(
            oracle,
            jobId,
            fee,
            currentMonth,
            previousMonth,
            block.timestamp,
            99e16
        );
    }

    function testDeploymentSucceedsWithCorrectStartingOraclePrice() public {
        l2scalingPriceOracle = new MockL2ScalingPriceOracle(
            oracle,
            jobId,
            fee,
            currentMonth,
            previousMonth,
            block.timestamp,
            2e18
        );
        assertEq(l2scalingPriceOracle.oraclePrice(), 2e18);
    }

    function testFulfillSucceedsTwentyPercentTwelveMonthsStartingOraclePriceTwo()
        public
    {
        l2scalingPriceOracle = new MockL2ScalingPriceOracle(
            oracle,
            jobId,
            fee,
            currentMonth,
            previousMonth,
            block.timestamp,
            2e18
        );
        assertEq(l2scalingPriceOracle.oraclePrice(), 2e18);
        vm.warp(block.timestamp + 33 days);
        uint256 newCurrentMonth = (currentMonth * 120) / 100;
        uint256 price = l2scalingPriceOracle.getCurrentOraclePrice();

        for (uint256 i = 0; i < 12; i++) {
            uint256 storedCurrentMonth = l2scalingPriceOracle.currentMonth();

            vm.warp(block.timestamp + 31 days);
            bytes32 requestId = l2scalingPriceOracle.requestCPIData();
            /// prank to allow request to be fulfilled
            vm.prank(address(0));
            /// this will succeed as max allowable is 20%
            l2scalingPriceOracle.fulfill(requestId, newCurrentMonth);
            assertEq(l2scalingPriceOracle.getCurrentOraclePrice(), price);

            uint256 expectedChangeRateBasisPoints = ((l2scalingPriceOracle
                .currentMonth() - l2scalingPriceOracle.previousMonth()) *
                10_000) / l2scalingPriceOracle.previousMonth();

            assertEq(
                l2scalingPriceOracle.monthlyChangeRateBasisPoints(),
                expectedChangeRateBasisPoints.toInt256()
            );
            assertEq(l2scalingPriceOracle.previousMonth(), storedCurrentMonth);
            assertEq(l2scalingPriceOracle.currentMonth(), newCurrentMonth);

            assertEq(l2scalingPriceOracle.oraclePrice(), price);

            newCurrentMonth =
                (newCurrentMonth * (10_000 + expectedChangeRateBasisPoints)) /
                10_000;
            price = (price * (10_000 + expectedChangeRateBasisPoints)) / 10_000;
        }
    }

    function testFulfillSucceedsTwentyPercentTwelveMonthsFuzz(uint128 x)
        public
    {
        /// instead of using vm.assume, do this to cut down on wasted runs
        if (x < 1e18) {
            vm.expectRevert(
                bytes("L2ScalingPriceOracle: Starting oracle price too low")
            );
        }

        l2scalingPriceOracle = new MockL2ScalingPriceOracle(
            oracle,
            jobId,
            fee,
            currentMonth,
            previousMonth,
            block.timestamp,
            x
        );
        if (x < 1e18) {
            return;
        }
        assertEq(l2scalingPriceOracle.oraclePrice(), x);
        vm.warp(block.timestamp + 33 days);
        uint256 newCurrentMonth = (currentMonth * 120) / 100;
        uint256 price = l2scalingPriceOracle.getCurrentOraclePrice();

        for (uint256 i = 0; i < 12; i++) {
            uint256 storedCurrentMonth = l2scalingPriceOracle.currentMonth();

            vm.warp(block.timestamp + 31 days);
            bytes32 requestId = l2scalingPriceOracle.requestCPIData();
            /// prank to allow request to be fulfilled
            vm.prank(address(0));
            /// this will succeed as max allowable is 20%
            l2scalingPriceOracle.fulfill(requestId, newCurrentMonth);
            assertEq(l2scalingPriceOracle.getCurrentOraclePrice(), price);

            uint256 expectedChangeRateBasisPoints = ((l2scalingPriceOracle
                .currentMonth() - l2scalingPriceOracle.previousMonth()) *
                10_000) / l2scalingPriceOracle.previousMonth();

            assertEq(
                l2scalingPriceOracle.monthlyChangeRateBasisPoints(),
                expectedChangeRateBasisPoints.toInt256()
            );
            assertEq(l2scalingPriceOracle.previousMonth(), storedCurrentMonth);
            assertEq(l2scalingPriceOracle.currentMonth(), newCurrentMonth);

            assertEq(l2scalingPriceOracle.oraclePrice(), price);

            newCurrentMonth =
                (newCurrentMonth * (10_000 + expectedChangeRateBasisPoints)) /
                10_000;
            price = (price * (10_000 + expectedChangeRateBasisPoints)) / 10_000;
        }
    }
}
