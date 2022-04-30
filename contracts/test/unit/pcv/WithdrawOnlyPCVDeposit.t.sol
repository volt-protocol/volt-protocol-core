// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IVolt} from "../../../volt/Volt.sol";
import {Volt} from "../../../volt/Volt.sol";
import {ICore} from "../../../core/ICore.sol";
import {Core} from "../../../core/Core.sol";
import {Vm} from "./../utils/Vm.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {getCore, getAddresses, FeiTestAddresses} from "./../utils/Fixtures.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {WithdrawOnlyPCVDeposit} from "./../../../pcv/WithdrawOnlyPCVDeposit.sol";
import {MockERC20} from "./../../../mock/MockERC20.sol";

contract WithdrawOnlyPCVDepositTest is DSTest {
    MockERC20 public token;

    IVolt private volt;
    Core private core;
    WithdrawOnlyPCVDeposit private deposit;

    Vm public constant vm = Vm(HEVM_ADDRESS);
    FeiTestAddresses public addresses = getAddresses();

    function setUp() public {
        token = new MockERC20();
        core = getCore();

        volt = core.volt();
        deposit = new WithdrawOnlyPCVDeposit(
            address(core),
            IERC20(address(token))
        );
    }

    function testTokenIsSet() public {
        assertEq(address(deposit.token()), address(token));
    }

    function testBalance() public {
        uint256 tokenAmount = 100;
        token.mint(address(deposit), tokenAmount);
        assertEq(deposit.balance(), tokenAmount);
    }

    function testBalanceReportedIn() public {
        assertEq(deposit.balanceReportedIn(), address(token));
    }

    function testWithdrawAsPCVController() public {
        uint256 tokenAmount = 100;
        token.mint(address(deposit), tokenAmount);

        vm.prank(addresses.pcvControllerAddress);
        deposit.withdraw(address(this), tokenAmount);

        assertEq(token.balanceOf(address(this)), tokenAmount);
    }

    function testWithdrawERC20AsPCVController() public {
        MockERC20 newToken = new MockERC20();

        uint256 tokenAmount = 100;
        newToken.mint(address(deposit), tokenAmount);

        vm.prank(addresses.pcvControllerAddress);
        deposit.withdrawERC20(address(newToken), address(this), tokenAmount);

        assertEq(newToken.balanceOf(address(this)), tokenAmount);
    }

    function testWithdrawFailsAsNonPCVController() public {
        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        deposit.withdraw(address(this), 1);
    }

    function testDepositFails() public {
        vm.expectRevert("WithdrawOnlyPCVDeposit: deposit not allowed");
        deposit.deposit();
    }
}
