// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";
import {MockERC20} from "../../../mock/MockERC20.sol";
import {MockPCVDepositV2} from "../../../mock/MockPCVDepositV2.sol";
import {getCore, getAddresses, FeiTestAddresses} from "./../utils/Fixtures.sol";
import {TribeRoles} from "../../../core/TribeRoles.sol";
import {ICore} from "../../../core/ICore.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {Vm} from "./../utils/Vm.sol";

contract PCVGuardianTest is DSTest {
    PCVGuardian private pcvGuardian;
    MockERC20 public underlyingToken;
    MockPCVDepositV2 public pcvDeposit;
    ICore private core;

    Vm public constant vm = Vm(HEVM_ADDRESS);
    FeiTestAddresses public addresses = getAddresses();

    address[] public whitelistAddresses;
    address public guard = address(0x123456789);

    uint256 public mintAmount = 10_000_000;

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
            address(this), // using 'this' address as the safe address for withdrawals
            whitelistAddresses
        );

        // grant the pcvGuardian the PCV controller and Guardian roles
        vm.startPrank(addresses.governorAddress);
        core.grantPCVController(address(pcvGuardian));
        core.grantGuardian(address(pcvGuardian));

        // create the PCV guard role, and grant it to the 'guard' address
        core.createRole(TribeRoles.PCV_GUARD, TribeRoles.GOVERNOR);
        core.grantRole(TribeRoles.PCV_GUARD, guard);

        underlyingToken.mint(address(pcvDeposit), mintAmount);
        pcvDeposit.deposit();
        vm.stopPrank();
    }

    function testPCVGuardianRoles() public view {
        assert(core.isGuardian(address(pcvGuardian)));
        assert(core.isPCVController(address(pcvGuardian)));
    }

    function testWithdrawToSafeAddress() public {
        vm.prank(addresses.governorAddress);
        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), mintAmount);

        assertEq(underlyingToken.balanceOf(address(this)), mintAmount);
    }

    function testGuardianWithdrawToSafeAddress() public {
        vm.prank(addresses.guardianAddress);
        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), mintAmount);

        assertEq(underlyingToken.balanceOf(address(this)), mintAmount);
    }

    function testPCVGuardWithdrawToSafeAddress() public {
        vm.prank(guard);
        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), mintAmount);

        assertEq(underlyingToken.balanceOf(address(this)), mintAmount);
    }

    function testWithdrawToSafeAddressFailWhenNoRole() public {
        vm.expectRevert(bytes("UNAUTHORIZED"));
        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), mintAmount);
    }

    function testWithdrawToSafeAddressFailWhenGuardRevoked() public {
        vm.prank(addresses.governorAddress);
        core.revokeRole(TribeRoles.PCV_GUARD, guard);

        vm.prank(guard);
        vm.expectRevert(bytes("UNAUTHORIZED"));

        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), mintAmount);
    }

    function testWithdrawToSafeAddressFailWhenNotWhitelist() public {
        vm.prank(addresses.governorAddress);
        vm.expectRevert(bytes("Provided address is not whitelisted"));

        pcvGuardian.withdrawToSafeAddress(address(0x1), mintAmount);
    }

    function testSetWhiteListAddress() public {
        vm.prank(addresses.governorAddress);

        pcvGuardian.setWhitelistAddress(address(0x123));
        assert(pcvGuardian.isWhitelistAddress(address(0x123)));
    }

    function testUnsetWhiteListAddress() public {
        vm.prank(addresses.governorAddress);

        pcvGuardian.unsetWhitelistAddress(address(pcvDeposit));
        assert(!pcvGuardian.isWhitelistAddress(address(pcvDeposit)));
    }
}
