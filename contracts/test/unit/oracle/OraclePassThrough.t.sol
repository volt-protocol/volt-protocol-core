// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Vm} from "./../utils/Vm.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {Decimal} from "./../../../external/Decimal.sol";
import {VoltSystemOracle} from "../../../oracle/VoltSystemOracle.sol";
import {OraclePassThrough} from "../../../oracle/OraclePassThrough.sol";
import {IScalingPriceOracle} from "../../../oracle/IScalingPriceOracle.sol";

contract UnitTestOraclePassThrough is DSTest {
    using Decimal for Decimal.D256;

    VoltSystemOracle private scalingPriceOracle;

    OraclePassThrough private oraclePassThrough;

    /// @notice increase price by 3.09% per month
    uint256 public constant monthlyChangeRateBasisPoints = 309;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    function setUp() public {
        /// warp to 1 to set isTimeStarted to true
        vm.warp(1);

        scalingPriceOracle = new VoltSystemOracle(
            monthlyChangeRateBasisPoints,
            1,
            1e18
        );

        oraclePassThrough = new OraclePassThrough(
            IScalingPriceOracle(address(scalingPriceOracle))
        );
    }

    function testSetup() public {
        assertEq(
            address(oraclePassThrough.scalingPriceOracle()),
            address(scalingPriceOracle)
        );
        assertEq(oraclePassThrough.owner(), address(this));
    }

    function testDataPassThroughSync() public {
        assertEq(
            oraclePassThrough.currPegPrice(),
            scalingPriceOracle.getCurrentOraclePrice()
        );
        assertEq(
            oraclePassThrough.getCurrentOraclePrice(),
            scalingPriceOracle.getCurrentOraclePrice()
        );

        (Decimal.D256 memory oPrice, bool oValid) = oraclePassThrough.read();
        assertEq(oPrice.value, scalingPriceOracle.getCurrentOraclePrice());
        assertTrue(oValid);
    }

    function testUpdateScalingPriceOracleFailureNotGovernor() public {
        vm.startPrank(address(0));
        vm.expectRevert(bytes("Ownable: caller is not the owner"));

        oraclePassThrough.updateScalingPriceOracle(
            IScalingPriceOracle(address(scalingPriceOracle))
        );
        vm.stopPrank();
    }

    function testUpdateScalingPriceOracleSuccess() public {
        IScalingPriceOracle newScalingPriceOracle = IScalingPriceOracle(
            address(new VoltSystemOracle(monthlyChangeRateBasisPoints, 1, 1e18))
        );

        oraclePassThrough.updateScalingPriceOracle(newScalingPriceOracle);

        /// assert that scaling price oracle was updated to new contract
        assertEq(
            address(newScalingPriceOracle),
            address(oraclePassThrough.scalingPriceOracle())
        );
    }
}
