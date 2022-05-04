// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";
import {MockERC20} from "../../../mock/MockERC20.sol";
import {MockPCVDepositV2} from "../../../mock/MockPCVDepositV2.sol";
import {getCore, getAddresses, FeiTestAddresses} from "./../utils/Fixtures.sol";
import {ICore} from "../../../core/ICore.sol";

import {DSTest} from "./../utils/DSTest.sol";
import {Vm} from "./../utils/Vm.sol";

contract PCVGuardianTest is DSTest {
    PCVGuardian private pcvGuardian;
    MockERC20 public underlyingToken;
    MockPCVDepositV2 public pcvDeposit;
    ICore private core;

    uint256 public mintAmount = 10_000_000;

    Vm public constant vm = Vm(HEVM_ADDRESS);
    FeiTestAddresses public addresses = getAddresses();

    address[] public whitelistAddresses;

    function setUp() public {
        core = getCore();

        underlyingToken = new MockERC20();
        pcvDeposit = new MockPCVDepositV2(
            address(core),
            address(underlyingToken),
            0,
            0
        );

        // whitelist the pcvDeposit as one of the addresses that can be withdrawn from
        whitelistAddresses.push(address(pcvDeposit));

        pcvGuardian = new PCVGuardian(
            address(core),
            address(this),
            whitelistAddresses
        );

        // grant the pcvGuardian the PCV controller and Guardian roles
        vm.startPrank(addresses.governorAddress);
        core.grantPCVController(address(pcvGuardian));
        core.grantGuardian(address(pcvGuardian));

        underlyingToken.mint(address(pcvDeposit), mintAmount);
        pcvDeposit.deposit();
        vm.stopPrank();
    }

    function testPCVGuardianRoles() public view {
        assert(core.isGuardian(address(pcvGuardian)));
        assert(core.isPCVController(address(pcvGuardian)));
    }

    function testPCVWithdrawToSafeAddress() public {
        vm.startPrank(addresses.governorAddress);

        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), mintAmount);

        assertEq(underlyingToken.balanceOf(address(this)), mintAmount);
    }

    function testPCVWithdrawToSafeAddressFailWhenNotWhitelist() public {
        vm.startPrank(addresses.governorAddress);
        vm.expectRevert("Provided address is not whitelisted");
        pcvGuardian.withdrawToSafeAddress(address(0x1), mintAmount);
    }

    function testPCVWithdrawToSafeAddressFailWhenNot() public {
        vm.startPrank(addresses.governorAddress);
        vm.expectRevert("Provided address is not whitelisted");
        pcvGuardian.withdrawToSafeAddress(address(0x1), mintAmount);
    }
}
