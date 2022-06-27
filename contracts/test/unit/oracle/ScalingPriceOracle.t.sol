// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Vm} from "./../utils/Vm.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {getCore, getAddresses, FeiTestAddresses} from "./../utils/Fixtures.sol";
import {MockScalingPriceOracle} from "../../../mock/MockScalingPriceOracle.sol";
import {MockChainlinkToken} from "../../../mock/MockChainlinkToken.sol";
import {Decimal} from "./../../../external/Decimal.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";

contract ScalingPriceOracleTest is DSTest {
    using Decimal for Decimal.D256;
    using SafeCast for *;

    MockScalingPriceOracle private scalingPriceOracle;

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

    function setUp() public {
        /// set this code at address 0 so _rawRequest in ChainlinkClient succeeds
        MockChainlinkToken token = new MockChainlinkToken();
        vm.etch(address(0), address(token).code);

        /// warp to 1 to set isTimeStarted to true
        vm.warp(1);

        scalingPriceOracle = new MockScalingPriceOracle(
            oracle,
            jobId,
            fee,
            currentMonth,
            previousMonth,
            address(0)
        );
    }

    function testSetup() public {
        assertEq(scalingPriceOracle.oracle(), oracle);
        assertEq(scalingPriceOracle.jobId(), jobId);
        assertEq(scalingPriceOracle.fee(), fee);
        assertEq(scalingPriceOracle.currentMonth(), currentMonth);
        assertEq(scalingPriceOracle.previousMonth(), previousMonth);
        assertEq(
            scalingPriceOracle.getMonthlyAPR(),
            monthlyChangeRateBasisPoints
        );
        assertEq(scalingPriceOracle.getChainlinkTokenAddress(), address(0));
    }

    /// positive price action from oracle -- inflation case
    function testReadGetCurrentOraclePriceAfterInterpolation() public {
        vm.warp(block.timestamp + 28 days);
        assertEq(10309e14, scalingPriceOracle.getCurrentOraclePrice());
    }

    /// negative price action from oracle -- deflation case
    function testPriceDecreaseAfterInterpolation() public {
        scalingPriceOracle = new MockScalingPriceOracle(
            oracle,
            jobId,
            fee,
            previousMonth, /// flip current and previous months so that rate is -3%
            currentMonth,
            address(0)
        );

        vm.warp(block.timestamp + 28 days);
        assertEq(97e16, scalingPriceOracle.getCurrentOraclePrice());
    }

    function testFulfillFailureTimed() public {
        assertTrue(!scalingPriceOracle.isTimeEnded());

        vm.expectRevert(bytes("Timed: time not ended, init"));

        scalingPriceOracle.requestCPIData();
    }

    function testFulfillMaxDeviationExceededFailureUp() public {
        vm.expectRevert(
            bytes(
                "ScalingPriceOracle: Chainlink data outside of deviation threshold"
            )
        );

        /// this will fail as it is 21% inflation and max allowable is 20%
        scalingPriceOracle.fulfill((currentMonth * 121) / 100);
    }

    function testFulfillFailsWhenNotChainlinkOracle() public {
        vm.warp(block.timestamp + 45 days);
        bytes32 requestId = scalingPriceOracle.requestCPIData();
        vm.expectRevert(bytes("Source must be the oracle of the request"));

        scalingPriceOracle.fulfill(requestId, currentMonth);
    }

    function testFulfillMaxDeviationExceededFailureDown() public {
        vm.expectRevert(
            bytes(
                "ScalingPriceOracle: Chainlink data outside of deviation threshold"
            )
        );

        /// this will fail as it is 21% inflation and max allowable is 20%
        scalingPriceOracle.fulfill((currentMonth * 79) / 100);
    }

    function testRequestSucceeds() public {
        vm.warp(block.timestamp + 45 days);
        uint256 oraclePrice = scalingPriceOracle.getCurrentOraclePrice();

        /// this will succeed and compound interest
        scalingPriceOracle.requestCPIData();

        uint256 storedPrice = scalingPriceOracle.oraclePrice();

        assertEq(oraclePrice, storedPrice);
    }

    function testFulfillSucceedsTwentyPercent() public {
        uint256 storedCurrentMonth = scalingPriceOracle.currentMonth();
        uint256 newCurrentMonth = (currentMonth * 120) / 100;

        /// this will succeed as max allowable is 20%
        scalingPriceOracle.fulfill(newCurrentMonth);

        assertEq(scalingPriceOracle.monthlyChangeRateBasisPoints(), 2_000);
        /// assert that all state transitions were done correctly with current and previous month
        assertEq(scalingPriceOracle.previousMonth(), storedCurrentMonth);
        assertEq(scalingPriceOracle.currentMonth(), newCurrentMonth);
    }

    function testFulfillSucceedsTwentyPercentTwoMonths() public {
        uint256 storedCurrentMonth = scalingPriceOracle.currentMonth();
        uint256 newCurrentMonth = (currentMonth * 120) / 100;

        /// this will succeed as max allowable is 20%
        scalingPriceOracle.fulfill(newCurrentMonth);

        assertEq(scalingPriceOracle.monthlyChangeRateBasisPoints(), 2_000);
        /// assert that all state transitions were done correctly with current and previous month
        assertEq(scalingPriceOracle.previousMonth(), storedCurrentMonth);
        assertEq(scalingPriceOracle.currentMonth(), newCurrentMonth);

        vm.warp(block.timestamp + 28 days);
        newCurrentMonth = (newCurrentMonth * 120) / 100;

        bytes32 requestId = scalingPriceOracle.requestCPIData();
        vm.prank(address(0));
        /// this will succeed as max allowable is 20%
        scalingPriceOracle.fulfill(requestId, newCurrentMonth);
        assertEq(scalingPriceOracle.oraclePrice(), 1.2e18);

        vm.warp(block.timestamp + 28 days);
        assertEq(
            scalingPriceOracle.getCurrentOraclePrice(),
            (1.2e18 * 120) / 100
        );

        requestId = scalingPriceOracle.requestCPIData();
        vm.prank(address(0));
        scalingPriceOracle.fulfill(requestId, newCurrentMonth);
        assertEq(scalingPriceOracle.oraclePrice(), (1.2e18 * 120) / 100);
    }

    function testFulfillSucceedsTwentyPercentTwelveMonths() public {
        vm.warp(block.timestamp + 46 days);
        uint256 newCurrentMonth = (currentMonth * 120) / 100;
        uint256 price = scalingPriceOracle.getCurrentOraclePrice();

        for (uint256 i = 0; i < 12; i++) {
            uint256 storedCurrentMonth = scalingPriceOracle.currentMonth();

            vm.warp(block.timestamp + 31 days);
            bytes32 requestId = scalingPriceOracle.requestCPIData();
            /// prank to allow request to be fulfilled
            vm.prank(address(0));
            /// this will succeed as max allowable is 20%
            scalingPriceOracle.fulfill(requestId, newCurrentMonth);
            assertEq(scalingPriceOracle.getCurrentOraclePrice(), price);

            uint256 expectedChangeRateBasisPoints = ((scalingPriceOracle
                .currentMonth() - scalingPriceOracle.previousMonth()) *
                10_000) / scalingPriceOracle.previousMonth();

            assertEq(
                scalingPriceOracle.monthlyChangeRateBasisPoints(),
                expectedChangeRateBasisPoints.toInt256()
            );
            assertEq(scalingPriceOracle.previousMonth(), storedCurrentMonth);
            assertEq(scalingPriceOracle.currentMonth(), newCurrentMonth);

            assertEq(scalingPriceOracle.oraclePrice(), price);

            newCurrentMonth =
                (newCurrentMonth * (10_000 + expectedChangeRateBasisPoints)) /
                10_000;
            price = (price * (10_000 + expectedChangeRateBasisPoints)) / 10_000;
        }
    }

    function testFulfillFailureCalendar() public {
        vm.warp(block.timestamp + 1647240109);

        vm.expectRevert(
            bytes("ScalingPriceOracle: cannot request data before the 15th")
        );

        scalingPriceOracle.requestCPIData();
    }
}
