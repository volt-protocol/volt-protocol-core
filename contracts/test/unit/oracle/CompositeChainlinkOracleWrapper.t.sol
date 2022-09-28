// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";

import {Vm} from "./../utils/Vm.sol";
import {ICore} from "../../../core/ICore.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {Decimal} from "./../../../external/Decimal.sol";
import {Constants} from "./../../../Constants.sol";
import {VoltSystemOracle} from "../../../oracle/VoltSystemOracle.sol";
import {OraclePassThrough} from "../../../oracle/OraclePassThrough.sol";
import {MockChainlinkOracle} from "./../../../mock/MockChainlinkOracle.sol";
import {CompositeChainlinkOracleWrapper} from "../../../oracle/CompositeChainlinkOracleWrapper.sol";
import {getCore, getAddresses, VoltTestAddresses} from "./../utils/Fixtures.sol";

contract CompositeChainlinkOracleWrapperUnitTest is DSTest {
    using Decimal for Decimal.D256;
    using SafeCast for *;

    ICore private core;

    MockChainlinkOracle private chainlinkOracle;

    VoltTestAddresses public addresses = getAddresses();

    /// @notice reference to the volt system oracle
    VoltSystemOracle private voltSystemOracle;

    /// @notice increase the volt target price by 2% monthly
    uint256 public constant monthlyChangeRateBasisPoints = 200;

    /// @notice block time at which the VSO (Volt System Oracle) will start accruing interest
    uint256 public constant startTime = 100_000;

    /// @notice actual starting oracle price on mainnet
    uint256 public constant startPrice = 1055095352308302897;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    CompositeChainlinkOracleWrapper private compositeOracle;

    int256 public constant compPrice = 100e8;
    uint8 public constant chainlinkOracleDecimals = 8;

    function setUp() public {
        core = getCore();
        voltSystemOracle = new VoltSystemOracle(
            monthlyChangeRateBasisPoints,
            startTime,
            startPrice
        );

        chainlinkOracle = new MockChainlinkOracle(
            compPrice,
            chainlinkOracleDecimals
        );

        compositeOracle = new CompositeChainlinkOracleWrapper(
            address(core),
            address(chainlinkOracle),
            OraclePassThrough(address(voltSystemOracle))
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
        assertEq(
            address(compositeOracle.oraclePassThrough()),
            address(voltSystemOracle)
        );
        assertEq(
            address(compositeOracle.chainlinkOracle()),
            address(chainlinkOracle)
        );
        assertEq(
            address(compositeOracle.chainlinkOracle()),
            address(chainlinkOracle)
        );
        assertEq(compositeOracle.oracleDecimalsNormalizer(), 1e8);
        assertTrue(!compositeOracle.isOutdated());
    }

    function testCompPricedCorrectlyInVolt(uint32 timeToPass) public {
        vm.warp(timeToPass);

        while (
            block.timestamp >=
            voltSystemOracle.periodStartTime() + voltSystemOracle.TIMEFRAME()
        ) {
            voltSystemOracle.compoundInterest();
        }

        uint256 voltPrice = voltSystemOracle.getCurrentOraclePrice();
        (Decimal.D256 memory compPricedInVolt, bool valid) = compositeOracle
            .read();

        assertTrue(valid);
        /// missing 10 decimals because comp price is only scaled up by 8 decimals
        /// then also about to lose 18 decimals by dividing by volt price which is scaled
        /// up by 18 decimals
        /// divide comp price by volt price to find out how many volt you need to pay for a single COMP token
        assertApproxEq(
            ((1e28 * compPrice.toUint256()) / voltPrice).toInt256(),
            compPricedInVolt.value.toInt256(),
            0
        );
    }

    function testUpdateNoOp() public view {
        compositeOracle.update();
    }

    function testUpdateNoOpFailsWhenPaused() public {
        vm.prank(addresses.governorAddress);
        compositeOracle.pause();
        vm.expectRevert("Pausable: paused");
        compositeOracle.update();
    }

    function testCompoundBeforePeriodStartFails() public {
        vm.expectRevert("VoltSystemOracle: not past end time");
        voltSystemOracle.compoundInterest();
    }
}
