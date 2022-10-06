// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ICore} from "../../core/ICore.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {TimelockSimulation} from "./utils/TimelockSimulation.sol";
import {IPCVGuardian} from "../../pcv/IPCVGuardian.sol";
import {vip13} from "./vip/vip13.sol";
import {stdError} from "../unit/utils/StdLib.sol";

contract IntegrationTestVoltMigratorTest is TimelockSimulation, vip13 {
    ICore core = ICore(MainnetAddresses.CORE);

    uint224 public constant mintAmount = 100_000_000e18;

    function setUp() public {
        simulate(
            getMainnetProposal(),
            TimelockController(payable(MainnetAddresses.TIMELOCK_CONTROLLER)),
            IPCVGuardian(MainnetAddresses.PCV_GUARDIAN),
            MainnetAddresses.GOVERNOR,
            MainnetAddresses.EOA_1,
            vm,
            false
        );
        mainnetValidate();

        vm.startPrank(MainnetAddresses.GOVERNOR);
        core.grantMinter(MainnetAddresses.GOVERNOR);
        oldVolt.mint(address(this), mintAmount);
        voltV2.mint(address(voltMigrator), mintAmount);
        vm.stopPrank();
    }

    function testExchange(uint64 amountOldVoltToExchange) public {
        oldVolt.approve(address(voltMigrator), type(uint256).max);

        uint256 oldVoltBalanceBefore = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceBefore = voltV2.balanceOf(address(this));

        voltMigrator.exchange(amountOldVoltToExchange);

        uint256 oldVoltBalanceAfter = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceAfter = voltV2.balanceOf(address(this));

        assertEq(
            newVoltBalanceAfter,
            newVoltBalanceBefore + amountOldVoltToExchange
        );
        assertEq(
            oldVoltBalanceAfter,
            oldVoltBalanceBefore - amountOldVoltToExchange
        );
    }

    function testExchangeTo(uint64 amountOldVoltToExchange) public {
        oldVolt.approve(address(voltMigrator), type(uint256).max);

        uint256 oldVoltBalanceBefore = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceBefore = voltV2.balanceOf(address(0xFFF));

        voltMigrator.exchangeTo(address(0xFFF), amountOldVoltToExchange);

        uint256 oldVoltBalanceAfter = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceAfter = voltV2.balanceOf(address(0xFFF));

        assertEq(
            newVoltBalanceAfter,
            newVoltBalanceBefore + amountOldVoltToExchange
        );
        assertEq(
            oldVoltBalanceAfter,
            oldVoltBalanceBefore - amountOldVoltToExchange
        );
    }

    function testExchangeAll() public {
        oldVolt.approve(address(voltMigrator), type(uint256).max);

        uint256 oldVoltBalanceBefore = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceBefore = voltV2.balanceOf(address(this));

        voltMigrator.exchangeAll();

        uint256 oldVoltBalanceAfter = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceAfter = voltV2.balanceOf(address(this));

        assertEq(
            newVoltBalanceAfter,
            newVoltBalanceBefore + oldVoltBalanceBefore
        );
        assertEq(oldVoltBalanceAfter, 0);
    }

    function testExchangeAllTo() public {
        oldVolt.approve(address(voltMigrator), type(uint256).max);

        uint256 oldVoltBalanceBefore = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceBefore = voltV2.balanceOf(address(0xFFF));

        voltMigrator.exchangeAllTo(address(0xFFF));

        uint256 oldVoltBalanceAfter = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceAfter = voltV2.balanceOf(address(0xFFF));

        assertEq(
            newVoltBalanceAfter,
            newVoltBalanceBefore + oldVoltBalanceBefore
        );
        assertEq(oldVoltBalanceAfter, 0);
    }

    function testExchangeFailsWhenApprovalNotGiven() public {
        vm.expectRevert("ERC20: burn amount exceeds allowance");
        voltMigrator.exchange(1e18);
    }

    function testExchangeToFailsWhenApprovalNotGiven() public {
        vm.expectRevert("ERC20: burn amount exceeds allowance");
        voltMigrator.exchangeTo(address(0xFFF), 1e18);
    }

    function testExchangeFailsMigratorUnderfunded() public {
        uint256 amountOldVoltToExchange = 100_000_000e18;
        oldVolt.approve(address(voltMigrator), type(uint256).max);

        vm.prank(address(voltMigrator));
        voltV2.burn(mintAmount);

        vm.expectRevert(stdError.arithmeticError);
        voltMigrator.exchange(amountOldVoltToExchange);
    }

    function testExchangeAllFailsMigratorUnderfunded() public {
        oldVolt.approve(address(voltMigrator), type(uint256).max);

        vm.prank(address(voltMigrator));
        voltV2.burn(mintAmount);

        vm.expectRevert(stdError.arithmeticError);
        voltMigrator.exchangeAll();
    }

    function testExchangeToFailsMigratorUnderfunded() public {
        uint256 amountOldVoltToExchange = 100_000_000e18;
        oldVolt.approve(address(voltMigrator), type(uint256).max);

        vm.prank(address(voltMigrator));
        voltV2.burn(mintAmount);

        vm.expectRevert(stdError.arithmeticError);
        voltMigrator.exchangeTo(address(0xFFF), amountOldVoltToExchange);
    }

    function testExchangeAllToFailsMigratorUnderfunded() public {
        oldVolt.approve(address(voltMigrator), type(uint256).max);

        vm.prank(address(voltMigrator));
        voltV2.burn(mintAmount);

        vm.expectRevert(stdError.arithmeticError);
        voltMigrator.exchangeAllTo(address(0xFFF));
    }

    function testExchangeAllWhenApprovalNotGiven() public {
        uint256 oldVoltBalanceBefore = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceBefore = voltV2.balanceOf(address(this));

        vm.expectRevert("VoltMigrator: no amount to exchange");
        voltMigrator.exchangeAll();

        uint256 oldVoltBalanceAfter = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceAfter = voltV2.balanceOf(address(this));

        assertEq(oldVoltBalanceBefore, oldVoltBalanceAfter);
        assertEq(newVoltBalanceBefore, newVoltBalanceAfter);
    }

    function testExchangeAllToWhenApprovalNotGiven() public {
        uint256 oldVoltBalanceBefore = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceBefore = voltV2.balanceOf(address(0xFFF));

        vm.expectRevert("VoltMigrator: no amount to exchange");
        voltMigrator.exchangeAllTo(address(0xFFF));

        uint256 oldVoltBalanceAfter = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceAfter = voltV2.balanceOf(address(0xFFF));

        assertEq(oldVoltBalanceBefore, oldVoltBalanceAfter);
        assertEq(newVoltBalanceBefore, newVoltBalanceAfter);
    }

    function testExchangeAllPartialApproval() public {
        uint256 amountOldVoltToExchange = 50_000_000e18;
        oldVolt.approve(address(voltMigrator), amountOldVoltToExchange);

        uint256 oldVoltBalanceBefore = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceBefore = voltV2.balanceOf(address(this));

        voltMigrator.exchangeAllTo(address(this));

        uint256 oldVoltBalanceAfter = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceAfter = voltV2.balanceOf(address(this));

        assertEq(
            newVoltBalanceAfter,
            newVoltBalanceBefore + amountOldVoltToExchange
        );
        assertEq(
            oldVoltBalanceAfter,
            oldVoltBalanceBefore - amountOldVoltToExchange
        );
    }

    function testExchangeAllToPartialApproval() public {
        uint256 amountOldVoltToExchange = 50_000_000e18;
        oldVolt.approve(address(voltMigrator), amountOldVoltToExchange);

        uint256 oldVoltBalanceBefore = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceBefore = voltV2.balanceOf(address(0xFFF));

        voltMigrator.exchangeAllTo(address(0xFFF));

        uint256 oldVoltBalanceAfter = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceAfter = voltV2.balanceOf(address(0xFFF));

        assertEq(
            newVoltBalanceAfter,
            newVoltBalanceBefore + amountOldVoltToExchange
        );
        assertEq(
            oldVoltBalanceAfter,
            oldVoltBalanceBefore - amountOldVoltToExchange
        );
    }
}
