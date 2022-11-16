// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Vm} from "./../utils/Vm.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {DynamicVoltRateModel} from "../../../oracle/DynamicVoltRateModel.sol";

contract DynamicVoltRateModelUnitTest is DSTest {
    Vm public constant vm = Vm(HEVM_ADDRESS);

    /// @notice reference to the volt system oracle
    DynamicVoltRateModel private rateModel;

    function setUp() public {
        rateModel = new DynamicVoltRateModel();
    }

    function testSetup() public {
        assertEq(rateModel.LIQUIDITY_JUMP_TARGET(), 0.3e18);
        assertEq(rateModel.MAXIMUM_CHANGE_RATE(), 0.5e18);
    }

    function testRateEnoughLiquidity() public {
        uint256 baseRate = 0.1e18; // 10%
        uint256 liquidPercentage = 0.5e18; // 50%
        assertEq(rateModel.getRate(baseRate, liquidPercentage), baseRate);
    }

    function testRateLowLiquidity() public {
        uint256 baseRate = 0.1e18; // 10%
        uint256 liquidPercentage = 0.15e18; // 15%
        assertEq(
            rateModel.getRate(baseRate, liquidPercentage),
            0.3e18 // 30%
        );
    }

    function testRateExtremes() public {
        // base rate = 0%, only yield = boost
        assertEq(rateModel.getRate(0, 0), 0.5e18);
        assertEq(rateModel.getRate(0, 0.3e18), 0);
        assertEq(rateModel.getRate(0, 1e18), 0);
        assertEq(rateModel.getRate(0, 9999e18), 0);
        // base rate = 10%, boost if < 30% liquid reserves
        assertEq(rateModel.getRate(0.1e18, 0), 0.5e18);
        assertEq(rateModel.getRate(0.1e18, 0.3e18), 0.1e18);
        assertEq(rateModel.getRate(0.1e18, 1e18), 0.1e18);
        assertEq(rateModel.getRate(0.1e18, 9999e18), 0.1e18);
        // base rate = 100%, above max rate, there is never any boost
        assertEq(rateModel.getRate(1e18, 0), 1e18);
        assertEq(rateModel.getRate(1e18, 0.3e18), 1e18);
        assertEq(rateModel.getRate(1e18, 1e18), 1e18);
        assertEq(rateModel.getRate(1e18, 9999e18), 1e18);
    }

    function testRateFuzz(uint256 baseRate, uint256 liquidReserves) public {
        vm.assume(baseRate < 100e18); // never set a base rate > 1000% APR
        vm.assume(liquidReserves <= 1e18); // percent of liquid reserves can't be >100%

        uint256 MAXIMUM_CHANGE_RATE = rateModel.MAXIMUM_CHANGE_RATE();
        uint256 LIQUIDITY_JUMP_TARGET = rateModel.LIQUIDITY_JUMP_TARGET();

        // if base rate greater than maximum rate, the function always returns the base rate
        if (baseRate > MAXIMUM_CHANGE_RATE) {
            assertEq(rateModel.getRate(baseRate, liquidReserves), baseRate);
        }
        // if there are enough liquid reserves, do not boost
        else if (liquidReserves > LIQUIDITY_JUMP_TARGET) {
            assertEq(rateModel.getRate(baseRate, liquidReserves), baseRate);
        }
        // otherwise, do a linear interpolation of the rate
        // use a different implementation to double check formula
        else {
            uint256 boost = _lerp(
                LIQUIDITY_JUMP_TARGET - liquidReserves,
                0, // min reserves for boost
                LIQUIDITY_JUMP_TARGET, // max reserves for boost
                0, // min boost
                MAXIMUM_CHANGE_RATE - baseRate // max boost
            );
            uint256 expectedRate = baseRate + boost;
            assertEq(rateModel.getRate(baseRate, liquidReserves), expectedRate);
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
    function _lerp(
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
}
