// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Vm} from "./../utils/Vm.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {DynamicVoltRateModel} from "../../../oracle/DynamicVoltRateModel.sol";

contract MarketGovernanceOracleUnitTest is DSTest {
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

    function testJumpRateEnoughLiquidity() public {
        uint256 baseRate = 0.1e18; // 10%
        uint256 liquidPercentage = 0.5e18; // 50%
        assertEq(rateModel.getRate(baseRate, liquidPercentage), baseRate);
    }

    function testJumpRateLowLiquidity() public {
        uint256 baseRate = 0.1e18; // 10%
        uint256 liquidPercentage = 0.15e18; // 15%
        assertEq(
            rateModel.getRate(baseRate, liquidPercentage),
            0.3e18 // 30%
        );
    }
}
