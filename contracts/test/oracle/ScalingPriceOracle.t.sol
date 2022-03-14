// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Vm} from "./../utils/Vm.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {getCore, getAddresses, FeiTestAddresses} from "./../utils/Fixtures.sol";
import {MockScalingPriceOracle} from "../../mock/MockScalingPriceOracle.sol";
import {Decimal} from "./../../external/Decimal.sol";

contract ScalingPriceOracleTest is DSTest {
    using Decimal for Decimal.D256;

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

    /// @notice minimum of 1 link
    uint256 public immutable minFee = 1e18;

    /// @notice maximum of 10 link
    uint256 public immutable maxFee = 1e19;

    Vm public constant vm = Vm(HEVM_ADDRESS);
    FeiTestAddresses public addresses = getAddresses();

    function setUp() public {
        /// warp to 1 to set isTimeStarted to true
        vm.warp(1);

        scalingPriceOracle = new MockScalingPriceOracle(
            oracle,
            jobId,
            minFee,
            maxFee,
            currentMonth,
            previousMonth
        );
    }

    function testSetup() public {
        assertEq(scalingPriceOracle.oracle(), oracle);
        assertEq(scalingPriceOracle.jobId(), jobId);
        assertEq(scalingPriceOracle.maxFee(), maxFee);
        assertEq(scalingPriceOracle.minFee(), minFee);
        assertEq(scalingPriceOracle.currentMonth(), currentMonth);
        assertEq(scalingPriceOracle.previousMonth(), previousMonth);
    }

    function testReadGetCurrentOraclePriceEquivalence() public {
        (Decimal.D256 memory price, bool valid) = scalingPriceOracle.read();
        assertEq(price.value, scalingPriceOracle.getCurrentOraclePrice());
        assertTrue(valid);
    }

    function testReadGetCurrentOraclePriceAfterInterpolation() public {
        vm.warp(block.timestamp + 28 days);
        assertEq(10309e14, scalingPriceOracle.getCurrentOraclePrice());
    }

    function testGetMonthlyAPR() public {
        assertEq(
            monthlyChangeRateBasisPoints,
            scalingPriceOracle.getMonthlyAPR()
        );
    }

    function testFulfillFailureTimed() public {
        assertTrue(!scalingPriceOracle.isTimeEnded());

        vm.expectRevert(bytes("Timed: time not ended, init"));

        scalingPriceOracle.requestCPIData(minFee);
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

    function testFulfillMaxDeviationExceededFailureDown() public {
        vm.expectRevert(
            bytes(
                "ScalingPriceOracle: Chainlink data outside of deviation threshold"
            )
        );

        /// this will fail as it is 21% inflation and max allowable is 20%
        scalingPriceOracle.fulfill((currentMonth * 79) / 100);
    }

    function testFulfillSucceedsTwentyPercent() public {
        /// this will succeed as max allowable is 20%
        scalingPriceOracle.fulfill((currentMonth * 120) / 100);

        assertEq(scalingPriceOracle.monthlyChangeRateBasisPoints(), 2_000);
    }

    function testFulfillFailureCalendar() public {
        vm.warp(block.timestamp + 1647240109);

        vm.expectRevert(
            bytes("ScalingPriceOracle: cannot request data before the 15th")
        );

        scalingPriceOracle.requestCPIData(maxFee);
    }

    function testFulfillFailureTooSmallFee() public {
        /// warp to get past timed error
        vm.warp(block.timestamp + 1647326509);

        vm.expectRevert(bytes("ScalingPriceOracle: fee less than min fee"));

        scalingPriceOracle.requestCPIData(minFee - 1);
    }

    function testFulfillFailureTooLargeFee() public {
        /// warp to get past timed error
        vm.warp(block.timestamp + 1647326509);

        vm.expectRevert(bytes("ScalingPriceOracle: fee greater than max fee"));

        scalingPriceOracle.requestCPIData(maxFee + 1);
    }
}
