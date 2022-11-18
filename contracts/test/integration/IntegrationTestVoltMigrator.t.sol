// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICore} from "../../core/ICore.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {TimelockSimulation} from "./utils/TimelockSimulation.sol";
import {IPCVGuardian} from "../../pcv/IPCVGuardian.sol";
import {vip13} from "./vip/vip13.sol";
import {stdError} from "../unit/utils/StdLib.sol";

contract IntegrationTestVoltMigratorTest is TimelockSimulation, vip13 {
    ICore core = ICore(MainnetAddresses.CORE);

    uint224 public constant mintAmount = 100_000_000e18;
    uint256 newVoltTotalSupply;

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
        coreV2.grantMinter(MainnetAddresses.GOVERNOR);
        oldVolt.mint(address(this), mintAmount);
        voltV2.mint(address(voltMigrator), mintAmount);
        vm.stopPrank();

        newVoltTotalSupply = voltV2.totalSupply();
        oldVoltTotalSupply = oldVolt.totalSupply();
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
        assertEq(
            oldVolt.totalSupply(),
            oldVoltTotalSupply - amountOldVoltToExchange
        );
        assertEq(voltV2.totalSupply(), newVoltTotalSupply);
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
        assertEq(
            oldVolt.totalSupply(),
            oldVoltTotalSupply - amountOldVoltToExchange
        );
        assertEq(voltV2.totalSupply(), newVoltTotalSupply);
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

        assertEq(
            oldVolt.totalSupply(),
            oldVoltTotalSupply - oldVoltBalanceBefore
        );
        assertEq(voltV2.totalSupply(), newVoltTotalSupply);
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
        assertEq(
            oldVolt.totalSupply(),
            oldVoltTotalSupply - oldVoltBalanceBefore
        );
        assertEq(voltV2.totalSupply(), newVoltTotalSupply);
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
        uint256 amountOldVoltToExchange = oldVolt.balanceOf(address(this)) / 2; // exchange half of users balance
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

        assertEq(
            oldVolt.totalSupply(),
            oldVoltTotalSupply - amountOldVoltToExchange
        );
        assertEq(voltV2.totalSupply(), newVoltTotalSupply);

        assertEq(oldVoltBalanceAfter, oldVoltBalanceBefore / 2);
    }

    function testExchangeAllToPartialApproval() public {
        uint256 amountOldVoltToExchange = oldVolt.balanceOf(address(this)) / 2; // exchange half of users balance
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
        assertEq(
            oldVolt.totalSupply(),
            oldVoltTotalSupply - amountOldVoltToExchange
        );
        assertEq(voltV2.totalSupply(), newVoltTotalSupply);
        assertEq(oldVoltBalanceAfter, oldVoltBalanceBefore / 2);
    }

    function testSweep() public {
        uint256 amountToTransfer = 1_000_000e6;
        IERC20 usdc = IERC20(MainnetAddresses.USDC);

        uint256 startingBalance = usdc.balanceOf(
            MainnetAddresses.TIMELOCK_CONTROLLER
        );

        vm.prank(MainnetAddresses.KRAKEN_USDC_WHALE);
        usdc.transfer(address(voltMigrator), amountToTransfer);

        vm.prank(MainnetAddresses.GOVERNOR);
        voltMigrator.sweep(
            address(usdc),
            MainnetAddresses.TIMELOCK_CONTROLLER,
            amountToTransfer
        );

        uint256 endingBalance = usdc.balanceOf(
            MainnetAddresses.TIMELOCK_CONTROLLER
        );

        assertEq(endingBalance - startingBalance, amountToTransfer);
    }

    function testSweepNonGovernorFails() public {
        uint256 amountToTransfer = 1_000_000e6;
        IERC20 usdc = IERC20(MainnetAddresses.USDC);

        vm.prank(MainnetAddresses.KRAKEN_USDC_WHALE);
        usdc.transfer(address(voltMigrator), amountToTransfer);

        vm.expectRevert("CoreRef: Caller is not a governor");
        voltMigrator.sweep(
            address(usdc),
            MainnetAddresses.TIMELOCK_CONTROLLER,
            amountToTransfer
        );
    }

    function testSweepNewVoltFails() public {
        uint256 amountToSweep = voltV2.balanceOf(address(voltMigrator));

        vm.startPrank(MainnetAddresses.GOVERNOR);
        vm.expectRevert("VoltMigrator: cannot sweep new Volt");
        voltMigrator.sweep(
            address(voltV2),
            MainnetAddresses.TIMELOCK_CONTROLLER,
            amountToSweep
        );
        vm.stopPrank();
    }
}
