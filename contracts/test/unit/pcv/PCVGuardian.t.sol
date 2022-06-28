// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";
import {PCVGuardAdmin} from "../../../pcv/PCVGuardAdmin.sol";
import {MockERC20} from "../../../mock/MockERC20.sol";
import {MockPCVDepositV2} from "../../../mock/MockPCVDepositV2.sol";
import {getCore, getAddresses, VoltTestAddresses} from "./../utils/Fixtures.sol";
import {TribeRoles} from "../../../core/TribeRoles.sol";
import {ICore} from "../../../core/ICore.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {Vm} from "./../utils/Vm.sol";

contract PCVGuardianTest is DSTest {
    PCVGuardian private pcvGuardian;
    PCVGuardAdmin private pcvGuardAdmin;
    MockERC20 public underlyingToken;
    MockERC20 public rewardToken;
    MockPCVDepositV2 public pcvDeposit;
    ICore private core;

    Vm public constant vm = Vm(HEVM_ADDRESS);
    VoltTestAddresses public addresses = getAddresses();

    address[] public whitelistAddresses;
    address public guard = address(0x123456789);

    uint256 public mintAmount = 10_000_000;

    function setUp() public {
        core = getCore();

        // acts as the underlying token in the pcv depost
        underlyingToken = new MockERC20();
        // acts as a yield / reward token in the pcv deposit
        rewardToken = new MockERC20();

        pcvDeposit = new MockPCVDepositV2(
            address(core),
            address(underlyingToken),
            0,
            0
        );

        pcvGuardAdmin = new PCVGuardAdmin(address(core));

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

        // create the PCV_GUARD_ADMIN role and grant it to the PCVGuardAdmin contract
        core.createRole(TribeRoles.PCV_GUARD_ADMIN, TribeRoles.GOVERNOR);
        core.grantRole(TribeRoles.PCV_GUARD_ADMIN, address(pcvGuardAdmin));

        // create the PCV guard role, and grant it to the 'guard' address
        core.createRole(TribeRoles.PCV_GUARD, TribeRoles.PCV_GUARD_ADMIN);
        pcvGuardAdmin.grantPCVGuardRole(guard);

        underlyingToken.mint(address(pcvDeposit), mintAmount);
        rewardToken.mint(address(pcvDeposit), mintAmount);
        pcvDeposit.deposit();
        vm.stopPrank();
    }

    function testPCVGuardianRoles() public {
        assertTrue(core.isGuardian(address(pcvGuardian)));
        assertTrue(core.isPCVController(address(pcvGuardian)));
    }

    function testPCVGuardAdminRole() public {
        assertTrue(
            core.hasRole(TribeRoles.PCV_GUARD_ADMIN, address(pcvGuardAdmin))
        );
    }

    function testPausedAfterWithdrawToSafeAddress() public {
        vm.startPrank(addresses.governorAddress);
        pcvDeposit.pause();
        assertEq(underlyingToken.balanceOf(address(this)), 0);

        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), mintAmount);
        vm.stopPrank();

        assertEq(underlyingToken.balanceOf(address(this)), mintAmount);
        assertTrue(pcvDeposit.paused());
    }

    function testWithdrawToSafeAddress() public {
        vm.startPrank(addresses.governorAddress);
        assertEq(underlyingToken.balanceOf(address(this)), 0);

        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), mintAmount);
        vm.stopPrank();

        assertEq(underlyingToken.balanceOf(address(this)), mintAmount);
    }

    function testGuardianWithdrawToSafeAddress() public {
        vm.startPrank(addresses.guardianAddress);
        assertEq(underlyingToken.balanceOf(address(this)), 0);

        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), mintAmount);
        vm.stopPrank();

        assertEq(underlyingToken.balanceOf(address(this)), mintAmount);
    }

    function testPCVGuardWithdrawToSafeAddress() public {
        vm.startPrank(guard);
        assertEq(underlyingToken.balanceOf(address(this)), 0);

        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), mintAmount);
        vm.stopPrank();

        assertEq(underlyingToken.balanceOf(address(this)), mintAmount);
    }

    function testWithdrawToSafeAddressFailWhenNoRole() public {
        vm.expectRevert(bytes("UNAUTHORIZED"));
        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), mintAmount);
    }

    function testWithdrawToSafeAddressFailWhenGuardRevokedGovernor() public {
        vm.prank(addresses.governorAddress);
        pcvGuardAdmin.revokePCVGuardRole(guard);

        vm.prank(guard);
        vm.expectRevert(bytes("UNAUTHORIZED"));

        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), mintAmount);
    }

    function testWithdrawToSafeAddressFailWhenGuardRevokedGuardian() public {
        vm.prank(addresses.guardianAddress);
        pcvGuardAdmin.revokePCVGuardRole(guard);

        vm.prank(guard);
        vm.expectRevert(bytes("UNAUTHORIZED"));

        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), mintAmount);
    }

    function testWithdrawToSafeAddressFailWhenNotWhitelist() public {
        vm.prank(addresses.governorAddress);
        vm.expectRevert(
            bytes("PCVGuardian: Provided address is not whitelisted")
        );

        pcvGuardian.withdrawToSafeAddress(address(0x1), mintAmount);
    }

    function testPausedAfterWithdrawAllToSafeAddress() public {
        vm.startPrank(addresses.governorAddress);
        pcvDeposit.pause();
        assertEq(underlyingToken.balanceOf(address(this)), 0);

        uint256 amountToWithdraw = pcvDeposit.balance();
        pcvGuardian.withdrawAllToSafeAddress(address(pcvDeposit));
        vm.stopPrank();

        assertEq(underlyingToken.balanceOf(address(this)), amountToWithdraw);
        assertTrue(pcvDeposit.paused());
    }

    function testWithdrawAllToSafeAddress() public {
        vm.startPrank(addresses.governorAddress);
        assertEq(underlyingToken.balanceOf(address(this)), 0);

        uint256 amountToWithdraw = pcvDeposit.balance();
        pcvGuardian.withdrawAllToSafeAddress(address(pcvDeposit));
        vm.stopPrank();

        assertEq(underlyingToken.balanceOf(address(this)), amountToWithdraw);
    }

    function testPCVGuardWithdrawAllToSafeAddress() public {
        vm.startPrank(guard);
        assertEq(underlyingToken.balanceOf(address(this)), 0);

        uint256 amountToWithdraw = pcvDeposit.balance();
        pcvGuardian.withdrawAllToSafeAddress(address(pcvDeposit));
        vm.stopPrank();

        assertEq(underlyingToken.balanceOf(address(this)), amountToWithdraw);
    }

    function testGuardianWithdrawAllToSafeAddress() public {
        vm.startPrank(addresses.guardianAddress);
        assertEq(underlyingToken.balanceOf(address(this)), 0);

        uint256 amountToWithdraw = pcvDeposit.balance();
        pcvGuardian.withdrawAllToSafeAddress(address(pcvDeposit));
        vm.stopPrank();

        assertEq(underlyingToken.balanceOf(address(this)), amountToWithdraw);
    }

    function testWithdrawAllToSafeAddressFailWhenNoRole() public {
        vm.expectRevert(bytes("UNAUTHORIZED"));
        pcvGuardian.withdrawAllToSafeAddress(address(pcvDeposit));
    }

    function testWithdrawAllToSafeAddressFailWhenGuardRevokedGovernor() public {
        vm.prank(addresses.governorAddress);
        pcvGuardAdmin.revokePCVGuardRole(guard);

        vm.prank(guard);
        vm.expectRevert(bytes("UNAUTHORIZED"));

        pcvGuardian.withdrawAllToSafeAddress(address(pcvDeposit));
    }

    function testWithdrawAllToSafeAddressFailWhenGuardRevokedGuardian() public {
        vm.prank(addresses.guardianAddress);
        pcvGuardAdmin.revokePCVGuardRole(guard);

        vm.prank(guard);
        vm.expectRevert(bytes("UNAUTHORIZED"));

        pcvGuardian.withdrawAllToSafeAddress(address(pcvDeposit));
    }

    function testWithdrawAlloSafeAddressFailWhenNotWhitelist() public {
        vm.prank(addresses.governorAddress);
        vm.expectRevert(
            bytes("PCVGuardian: Provided address is not whitelisted")
        );

        pcvGuardian.withdrawAllToSafeAddress(address(0x1));
    }

    function testGovernorWithdrawERC20ToSafeAddress() public {
        vm.startPrank(addresses.governorAddress);
        assertEq(rewardToken.balanceOf(address(this)), 0);

        pcvGuardian.withdrawERC20ToSafeAddress(
            address(pcvDeposit),
            address(rewardToken),
            mintAmount
        );
        vm.stopPrank();

        assertEq(rewardToken.balanceOf(address(this)), mintAmount);
    }

    function testGuardianWithdrawERC20ToSafeAddress() public {
        vm.startPrank(addresses.guardianAddress);
        assertEq(rewardToken.balanceOf(address(this)), 0);

        pcvGuardian.withdrawERC20ToSafeAddress(
            address(pcvDeposit),
            address(rewardToken),
            mintAmount
        );
        vm.stopPrank();

        assertEq(rewardToken.balanceOf(address(this)), mintAmount);
    }

    function testPCVGuardWithdrawERC20ToSafeAddress() public {
        vm.startPrank(guard);
        assertEq(rewardToken.balanceOf(address(this)), 0);

        pcvGuardian.withdrawERC20ToSafeAddress(
            address(pcvDeposit),
            address(rewardToken),
            mintAmount
        );
        vm.stopPrank();

        assertEq(rewardToken.balanceOf(address(this)), mintAmount);
    }

    function testWithdrawERC20ToSafeAddressFailWhenNoRole() public {
        vm.expectRevert(bytes("UNAUTHORIZED"));
        pcvGuardian.withdrawERC20ToSafeAddress(
            address(pcvDeposit),
            address(rewardToken),
            mintAmount
        );
    }

    function testWithdrawERC20ToSafeAddressFailWhenGuardRevokedGovernor()
        public
    {
        vm.prank(addresses.governorAddress);
        pcvGuardAdmin.revokePCVGuardRole(guard);

        vm.prank(guard);
        vm.expectRevert(bytes("UNAUTHORIZED"));

        pcvGuardian.withdrawERC20ToSafeAddress(
            address(pcvDeposit),
            address(rewardToken),
            mintAmount
        );
    }

    function testWithdrawERC20ToSafeAddressFailWhenGuardRevokedGuardian()
        public
    {
        vm.prank(addresses.guardianAddress);
        pcvGuardAdmin.revokePCVGuardRole(guard);

        vm.prank(guard);
        vm.expectRevert(bytes("UNAUTHORIZED"));

        pcvGuardian.withdrawERC20ToSafeAddress(
            address(pcvDeposit),
            address(rewardToken),
            mintAmount
        );
    }

    function testWithdrawERC20oSafeAddressFailWhenNotWhitelist() public {
        vm.prank(addresses.governorAddress);
        vm.expectRevert(
            bytes("PCVGuardian: Provided address is not whitelisted")
        );

        pcvGuardian.withdrawERC20ToSafeAddress(
            address(0x1),
            address(rewardToken),
            mintAmount
        );
    }

    function testGovernorWithdrawAllERC20ToSafeAddress() public {
        vm.startPrank(addresses.governorAddress);
        assertEq(rewardToken.balanceOf(address(this)), 0);

        pcvGuardian.withdrawAllERC20ToSafeAddress(
            address(pcvDeposit),
            address(rewardToken)
        );
        vm.stopPrank();

        assertEq(rewardToken.balanceOf(address(this)), mintAmount);
    }

    function testGuardianWithdrawAllERC20ToSafeAddress() public {
        vm.startPrank(addresses.guardianAddress);
        assertEq(rewardToken.balanceOf(address(this)), 0);

        pcvGuardian.withdrawAllERC20ToSafeAddress(
            address(pcvDeposit),
            address(rewardToken)
        );
        vm.stopPrank();

        assertEq(rewardToken.balanceOf(address(this)), mintAmount);
    }

    function testPCVGuardWithdrawAllERC20ToSafeAddress() public {
        vm.startPrank(guard);
        assertEq(rewardToken.balanceOf(address(this)), 0);

        pcvGuardian.withdrawAllERC20ToSafeAddress(
            address(pcvDeposit),
            address(rewardToken)
        );
        vm.stopPrank();

        assertEq(rewardToken.balanceOf(address(this)), mintAmount);
    }

    function testWithdrawAllERC20ToSafeAddressFailWhenNoRole() public {
        vm.expectRevert(bytes("UNAUTHORIZED"));
        pcvGuardian.withdrawAllERC20ToSafeAddress(
            address(pcvDeposit),
            address(rewardToken)
        );
    }

    function testWithdrawAllERC20ToSafeAddressFailWhenGuardRevokedGovernor()
        public
    {
        vm.prank(addresses.governorAddress);
        pcvGuardAdmin.revokePCVGuardRole(guard);

        vm.prank(guard);
        vm.expectRevert(bytes("UNAUTHORIZED"));

        pcvGuardian.withdrawAllERC20ToSafeAddress(
            address(pcvDeposit),
            address(rewardToken)
        );
    }

    function testWithdrawAllERC20ToSafeAddressFailWhenGuardRevokedGuardian()
        public
    {
        vm.prank(addresses.guardianAddress);
        pcvGuardAdmin.revokePCVGuardRole(guard);

        vm.prank(guard);
        vm.expectRevert(bytes("UNAUTHORIZED"));

        pcvGuardian.withdrawAllERC20ToSafeAddress(
            address(pcvDeposit),
            address(rewardToken)
        );
    }

    function testWithdrawAllERC20ToSafeAddressFailWhenNotWhitelist() public {
        vm.prank(addresses.governorAddress);
        vm.expectRevert(
            bytes("PCVGuardian: Provided address is not whitelisted")
        );

        pcvGuardian.withdrawAllERC20ToSafeAddress(
            address(0x1),
            address(rewardToken)
        );
    }

    function testAddWhiteListAddress() public {
        vm.prank(addresses.governorAddress);

        pcvGuardian.addWhitelistAddress(address(0x123));
        assertTrue(pcvGuardian.isWhitelistAddress(address(0x123)));
    }

    function testRemoveWhiteListAddress() public {
        vm.prank(addresses.governorAddress);

        pcvGuardian.removeWhitelistAddress(address(pcvDeposit));
        assertTrue(!pcvGuardian.isWhitelistAddress(address(pcvDeposit)));
    }
}
