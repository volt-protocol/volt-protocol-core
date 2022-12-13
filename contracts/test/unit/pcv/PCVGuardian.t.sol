// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Vm} from "./../utils/Vm.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {ICoreV2} from "../../../core/ICoreV2.sol";
import {VoltRoles} from "../../../core/VoltRoles.sol";
import {MockERC20} from "../../../mock/MockERC20.sol";
import {getCoreV2} from "./../utils/Fixtures.sol";
import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";
import {SystemEntry} from "../../../entry/SystemEntry.sol";
import {MockPCVDepositV2} from "../../../mock/MockPCVDepositV2.sol";
import {TestAddresses as addresses} from "../utils/TestAddresses.sol";
import {IGlobalReentrancyLock, GlobalReentrancyLock} from "../../../core/GlobalReentrancyLock.sol";

contract UnitTestPCVGuardian is DSTest {
    event SafeAddressUpdated(
        address indexed oldSafeAddress,
        address indexed newSafeAddress
    );

    ICoreV2 private core;
    SystemEntry public entry;
    MockERC20 public rewardToken;
    PCVGuardian private pcvGuardian;
    MockERC20 public underlyingToken;
    MockPCVDepositV2 public pcvDeposit;
    IGlobalReentrancyLock private lock;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    address[] public whitelistAddresses;
    address public guard = address(0x123456789);

    uint256 public mintAmount = 10_000_000;

    function setUp() public {
        core = getCoreV2();
        entry = new SystemEntry(address(core));
        lock = IGlobalReentrancyLock(
            address(new GlobalReentrancyLock(address(core)))
        );

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

        /// whitelist the pcvDeposit as one of the addresses that can be withdrawn from
        whitelistAddresses.push(address(pcvDeposit));

        pcvGuardian = new PCVGuardian(
            address(core),
            address(this), /// using 'this' address as the safe address for withdrawals
            whitelistAddresses
        );

        /// grant the pcvGuardian the PCV controller and Guardian roles
        vm.startPrank(addresses.governorAddress);
        core.setGlobalReentrancyLock(lock);

        core.grantPCVController(address(pcvGuardian));
        core.grantGuardian(address(pcvGuardian));

        core.grantLocker(address(entry));
        core.grantLocker(address(pcvDeposit));
        core.grantLocker(address(pcvGuardian));

        /// grant the PCV guard role to the 'guard' address
        core.grantPCVGuard(guard);

        underlyingToken.mint(address(pcvDeposit), mintAmount);
        rewardToken.mint(address(pcvDeposit), mintAmount);
        entry.deposit(address(pcvDeposit));
        vm.stopPrank();
    }

    function testPCVGuardianRoles() public {
        assertTrue(core.isLocker(address(entry)));
        assertTrue(core.isLocker(address(pcvDeposit)));
        assertTrue(core.isLocker(address(pcvGuardian)));
        assertTrue(core.isGuardian(address(pcvGuardian)));
        assertTrue(core.isPCVController(address(pcvGuardian)));
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
        core.revokePCVGuard(guard);

        vm.prank(guard);
        vm.expectRevert(bytes("UNAUTHORIZED"));

        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), mintAmount);
    }

    function testWithdrawToSafeAddressFailWhenGuardRevokedGuardian() public {
        vm.prank(addresses.guardianAddress);
        core.revokeOverride(VoltRoles.PCV_GUARD, guard);

        vm.prank(guard);
        vm.expectRevert("UNAUTHORIZED");

        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), mintAmount);
    }

    function testWithdrawToSafeAddressFailWhenNotWhitelist() public {
        vm.prank(addresses.governorAddress);
        vm.expectRevert("PCVGuardian: Provided address is not whitelisted");

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
        core.revokePCVGuard(guard);

        vm.prank(guard);
        vm.expectRevert(bytes("UNAUTHORIZED"));

        pcvGuardian.withdrawAllToSafeAddress(address(pcvDeposit));
    }

    function testWithdrawAllToSafeAddressFailWhenGuardRevokedGuardian() public {
        vm.prank(addresses.guardianAddress);
        core.revokeOverride(VoltRoles.PCV_GUARD, guard);

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
        core.revokePCVGuard(guard);

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
        core.revokeOverride(VoltRoles.PCV_GUARD, guard);

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
        core.revokePCVGuard(guard);

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
        vm.prank(addresses.governorAddress);
        core.revokePCVGuard(guard);

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

    function testAddWhiteListAddressNonGovernorFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        pcvGuardian.addWhitelistAddress(address(0x123));
    }

    function testAddWhiteListAddressesNonGovernorFails() public {
        address[] memory toWhitelist = new address[](1);
        vm.expectRevert("CoreRef: Caller is not a governor");
        pcvGuardian.addWhitelistAddresses(toWhitelist);
    }

    function testAddWhiteListAddressesGovernorSucceeds(
        address newDeposit
    ) public {
        vm.assume(!pcvGuardian.isWhitelistAddress(newDeposit));

        address[] memory toWhitelist = new address[](1);
        toWhitelist[0] = newDeposit;
        vm.prank(addresses.governorAddress);
        pcvGuardian.addWhitelistAddresses(toWhitelist);
        assertTrue(pcvGuardian.isWhitelistAddress(newDeposit));
    }

    function testRemoveWhiteListAddress() public {
        vm.prank(addresses.governorAddress);

        pcvGuardian.removeWhitelistAddress(address(pcvDeposit));
        assertTrue(!pcvGuardian.isWhitelistAddress(address(pcvDeposit)));
    }

    function testSetSafeAddressNonGovernorFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        pcvGuardian.setSafeAddress(address(0));
    }

    function testSetSafeAddressGovernorSucceeds() public {
        vm.expectEmit(true, true, false, true, address(pcvGuardian));
        emit SafeAddressUpdated(address(this), address(0));
        vm.prank(addresses.governorAddress);
        pcvGuardian.setSafeAddress(address(0));
        assertEq(pcvGuardian.safeAddress(), address(0));
    }
}
