// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Vm} from "./../utils/Vm.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {getCore, getAddresses, FeiTestAddresses} from "./../utils/Fixtures.sol";
import {MockScalingPriceOracle} from "../../../mock/MockScalingPriceOracle.sol";
import {VoltSystemOracle} from "../../../oracle/VoltSystemOracle.sol";
import {ScalingPriceOracle} from "../../../oracle/ScalingPriceOracle.sol";
import {MockChainlinkToken} from "../../../mock/MockChainlinkToken.sol";
import {Decimal} from "./../../../external/Decimal.sol";
import {Constants} from "./../../../Constants.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";

contract VoltSystemOracleTest is DSTest {
    using Decimal for Decimal.D256;
    using SafeCast for *;

    MockScalingPriceOracle private scalingPriceOracle;

    /// @notice reference to the volt system oracle
    VoltSystemOracle private voltSystemOracle;

    /// @notice increase price by 3.09% per month
    int256 public constant monthlyChangeRateBasisPoints = 309;

    /// @notice increase the volt target price by 2% annually
    uint256 public constant annualChangeRateBasisPoints = 200;

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

    uint256 public constant startTime = 100_000;

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

        voltSystemOracle = new VoltSystemOracle(
            annualChangeRateBasisPoints,
            startTime,
            ScalingPriceOracle(address(scalingPriceOracle))
        );
    }

    function testSetup() public {
        assertEq(voltSystemOracle.oraclePrice(), 1 ether);
        assertEq(
            voltSystemOracle.annualChangeRateBasisPoints(),
            annualChangeRateBasisPoints
        );
        assertEq(
            address(voltSystemOracle.scalingPriceOracle()),
            address(scalingPriceOracle)
        );
        assertEq(voltSystemOracle.oracleStartTime(), startTime);
        assertEq(voltSystemOracle.startTime(), block.timestamp);
        assertEq(voltSystemOracle.getCurrentOraclePrice(), 1e18);
    }

    function testInitFailsBeforeStartTime() public {
        vm.expectRevert("VoltSystemOracle: not past start time");

        voltSystemOracle.init();
    }

    function testSecondInitFails() public {
        vm.warp(voltSystemOracle.oracleStartTime());

        voltSystemOracle.init();

        vm.expectRevert("Initializable: contract is already initialized");
        voltSystemOracle.init();
    }

    function testCompoundBeforeInitFails() public {
        vm.expectRevert("Timed: time not ended");
        voltSystemOracle.compoundInterest();
    }

    function testInitSucceeds() public {
        assertEq(voltSystemOracle.startTime(), 1); /// start time starts at block.timestamp
        vm.warp(voltSystemOracle.oracleStartTime());

        voltSystemOracle.init();

        /// start time is successfully set
        assertEq(
            voltSystemOracle.startTime(),
            voltSystemOracle.oracleStartTime()
        );
        /// spo and vso are perfectly in sync when init happens
        assertEq(
            voltSystemOracle.getCurrentOraclePrice(),
            scalingPriceOracle.getCurrentOraclePrice()
        );
        assertEq(
            voltSystemOracle.oraclePrice(),
            scalingPriceOracle.getCurrentOraclePrice()
        );
    }

    function testCompoundSucceedsAfterOneYear() public {
        assertEq(voltSystemOracle.oraclePrice(), 1 ether);
        vm.warp(block.timestamp + voltSystemOracle.oracleStartTime());

        voltSystemOracle.init();
        uint256 oraclePrice = scalingPriceOracle.getCurrentOraclePrice();

        vm.warp(block.timestamp + 365 days);

        assertEq(
            voltSystemOracle.getCurrentOraclePrice(),
            (oraclePrice *
                (Constants.BASIS_POINTS_GRANULARITY +
                    annualChangeRateBasisPoints)) /
                Constants.BASIS_POINTS_GRANULARITY
        );
        voltSystemOracle.compoundInterest();
        assertEq(
            voltSystemOracle.oraclePrice(),
            (oraclePrice *
                (Constants.BASIS_POINTS_GRANULARITY +
                    annualChangeRateBasisPoints)) /
                Constants.BASIS_POINTS_GRANULARITY
        );
    }

    function testLinearInterpolation() public {
        assertEq(voltSystemOracle.oraclePrice(), 1 ether);
        vm.warp(voltSystemOracle.oracleStartTime() + 365 days);

        assertEq(
            voltSystemOracle.getCurrentOraclePrice(),
            (1e18 *
                (Constants.BASIS_POINTS_GRANULARITY +
                    annualChangeRateBasisPoints)) /
                Constants.BASIS_POINTS_GRANULARITY
        );
    }

    function testLinearInterpolationFuzz(uint32 timeIncrease) public {
        vm.warp(block.timestamp + voltSystemOracle.oracleStartTime());
        voltSystemOracle.init();
        uint256 cachedOraclePrice = voltSystemOracle.oraclePrice();

        vm.warp(block.timestamp + timeIncrease);

        if (timeIncrease >= 365 days) {
            assertEq(
                voltSystemOracle.getCurrentOraclePrice(),
                (cachedOraclePrice *
                    (Constants.BASIS_POINTS_GRANULARITY +
                        annualChangeRateBasisPoints)) /
                    Constants.BASIS_POINTS_GRANULARITY
            );
        } else {
            uint256 timeDelta = voltSystemOracle.timeSinceStart();
            uint256 pricePercentageChange = (cachedOraclePrice *
                voltSystemOracle.annualChangeRateBasisPoints()) /
                Constants.BASIS_POINTS_GRANULARITY;
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
        /// get past start time and then initialize the volt system oracle
        vm.warp(block.timestamp + voltSystemOracle.oracleStartTime());
        voltSystemOracle.init();

        for (uint256 i = 0; i < cycles; i++) {
            vm.warp(block.timestamp + timeIncrease);

            uint256 cachedOraclePrice = voltSystemOracle.oraclePrice();

            /// ensure interest accrues properly before compounding
            if (timeIncrease >= 365 days) {
                assertEq(
                    voltSystemOracle.getCurrentOraclePrice(),
                    (cachedOraclePrice *
                        (Constants.BASIS_POINTS_GRANULARITY +
                            annualChangeRateBasisPoints)) /
                        Constants.BASIS_POINTS_GRANULARITY
                );
            } else {
                uint256 timeDelta = voltSystemOracle.timeSinceStart();
                uint256 pricePercentageChange = (cachedOraclePrice *
                    voltSystemOracle.annualChangeRateBasisPoints()) /
                    Constants.BASIS_POINTS_GRANULARITY;
                uint256 priceDelta = (pricePercentageChange * timeDelta) /
                    365 days;
                assertEq(
                    voltSystemOracle.getCurrentOraclePrice(),
                    priceDelta + cachedOraclePrice
                );
            }

            if (voltSystemOracle.isTimeEnded()) {
                voltSystemOracle.compoundInterest();
                /// ensure accumulator updates correctly on interest compounding
                assertEq(
                    voltSystemOracle.oraclePrice(),
                    (cachedOraclePrice *
                        (Constants.BASIS_POINTS_GRANULARITY +
                            annualChangeRateBasisPoints)) /
                        Constants.BASIS_POINTS_GRANULARITY
                );
            }
        }
    }
}
