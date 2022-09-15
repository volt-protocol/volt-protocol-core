// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ICore} from "../../core/ICore.sol";
import {IVolt, Volt} from "../../volt/Volt.sol";
import {VoltMigrator} from "../../volt/VoltMigrator.sol";
import {VoltV2} from "../../volt/VoltV2.sol";
import {Vm} from "./../unit/utils/Vm.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";

contract IntegrationTestVoltMigratorTest is DSTest {
    VoltMigrator private voltMigrator;
    VoltV2 private newVolt;

    IVolt oldVolt = IVolt(MainnetAddresses.VOLT);
    ICore core = ICore(MainnetAddresses.CORE);

    Vm public constant vm = Vm(HEVM_ADDRESS);

    uint256 public constant mintAmount = 100_000_000e18;

    function setUp() public {
        newVolt = new VoltV2(MainnetAddresses.CORE);
        voltMigrator = new VoltMigrator(
            MainnetAddresses.CORE,
            address(newVolt)
        );

        vm.startPrank(MainnetAddresses.GOVERNOR);
        core.grantMinter(MainnetAddresses.GOVERNOR);
        // mint old volt to user
        oldVolt.mint(address(this), mintAmount);
        // mint new volt to migrator contract
        newVolt.mint(address(voltMigrator), mintAmount);
        vm.stopPrank();

        oldVolt.approve(address(voltMigrator), type(uint256).max);
    }

    function testExchange(uint64 amountOldVoltToExchange) public {
        uint256 oldVoltBalanceBefore = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceBefore = newVolt.balanceOf(address(this));

        voltMigrator.exchange(amountOldVoltToExchange);

        uint256 oldVoltBalanceAfter = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceAfter = newVolt.balanceOf(address(this));

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
        uint256 oldVoltBalanceBefore = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceBefore = newVolt.balanceOf(address(this));

        voltMigrator.exchangeAll();

        uint256 oldVoltBalanceAfter = oldVolt.balanceOf(address(this));
        uint256 newVoltBalanceAfter = newVolt.balanceOf(address(this));

        assertEq(
            newVoltBalanceAfter,
            newVoltBalanceBefore + oldVoltBalanceBefore
        );
        assertEq(oldVoltBalanceAfter, 0);
    }
}
