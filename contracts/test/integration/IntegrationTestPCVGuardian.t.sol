// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {PCVGuardian} from "../../pcv/PCVGuardian.sol";
import {PCVGuardAdmin} from "../../pcv/PCVGuardAdmin.sol";

import {TribeRoles} from "../../core/TribeRoles.sol";
import {ICore} from "../../core/ICore.sol";
import {IVolt} from "../../volt/Volt.sol";
import {IPCVDeposit} from "../../pcv/IPCVDeposit.sol";
import {getMainnetAddresses, VoltTestAddresses} from "../unit/utils/Fixtures.sol";
import {DSTest} from "../unit/utils/DSTest.sol";
import {Vm} from "../unit/utils/Vm.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";

interface IPCVDepositTest is IPCVDeposit {
    function pause() external;

    function paused() external view returns (bool);
}

contract IntegrationTestPCVGuardian is DSTest {
    PCVGuardian private pcvGuardian;
    PCVGuardAdmin private pcvGuardAdmin;

    ICore private core = ICore(MainnetAddresses.CORE);
    IVolt private fei = IVolt(MainnetAddresses.FEI);

    IPCVDepositTest private pcvDeposit =
        IPCVDepositTest(MainnetAddresses.VOLT_FEI_PSM);

    Vm public constant vm = Vm(HEVM_ADDRESS);

    address[] public whitelistAddresses;
    address public guard = address(0x123456789);

    uint256 public withdrawAmount = fei.balanceOf(address(pcvDeposit));

    function setUp() public {
        whitelistAddresses.push(address(pcvDeposit));

        pcvGuardian = new PCVGuardian(
            address(core),
            address(this), // using 'this' address as the safe address for withdrawals
            whitelistAddresses
        );

        pcvGuardAdmin = new PCVGuardAdmin(address(core));

        // grant the pcvGuardian the PCV controller and Guardian roles
        vm.startPrank(MainnetAddresses.GOVERNOR);
        core.grantPCVController(address(pcvGuardian));
        core.grantGuardian(address(pcvGuardian));

        // create the PCV_GUARD_ADMIN role and grant it to the PCVGuardAdmin contract
        core.createRole(TribeRoles.PCV_GUARD_ADMIN, TribeRoles.GOVERNOR);
        core.grantRole(TribeRoles.PCV_GUARD_ADMIN, address(pcvGuardAdmin));

        // create the PCV guard role, and grant it to the 'guard' address
        core.createRole(TribeRoles.PCV_GUARD, TribeRoles.PCV_GUARD_ADMIN);
        pcvGuardAdmin.grantPCVGuardRole(guard);
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
        vm.startPrank(MainnetAddresses.GOVERNOR);
        pcvDeposit.pause();
        assertEq(fei.balanceOf(address(this)), 0);

        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), withdrawAmount);
        vm.stopPrank();

        assertEq(fei.balanceOf(address(this)), withdrawAmount);
        assertTrue(pcvDeposit.paused());
    }

    function testGovernorWithdrawToSafeAddress() public {
        vm.startPrank(MainnetAddresses.GOVERNOR);
        assertEq(fei.balanceOf(address(this)), 0);

        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), withdrawAmount);
        vm.stopPrank();

        assertEq(fei.balanceOf(address(this)), withdrawAmount);
    }

    function testPausedAfterWithdrawAllToSafeAddress() public {
        vm.startPrank(MainnetAddresses.GOVERNOR);
        pcvDeposit.pause();
        assertEq(fei.balanceOf(address(this)), 0);

        uint256 amountToWithdraw = pcvDeposit.balance();
        pcvGuardian.withdrawAllToSafeAddress(address(pcvDeposit));
        vm.stopPrank();

        assertEq(fei.balanceOf(address(this)), amountToWithdraw);
        assertTrue(pcvDeposit.paused());
    }

    function testGovernorWithdrawAllToSafeAddress() public {
        vm.startPrank(MainnetAddresses.GOVERNOR);
        assertEq(fei.balanceOf(address(this)), 0);

        uint256 amountToWithdraw = pcvDeposit.balance();
        pcvGuardian.withdrawAllToSafeAddress(address(pcvDeposit));
        vm.stopPrank();

        assertEq(fei.balanceOf(address(this)), amountToWithdraw);
    }

    function testGuardianWithdrawToSafeAddress() public {
        vm.startPrank(MainnetAddresses.GUARDIAN);

        assertEq(fei.balanceOf(address(this)), 0);
        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), withdrawAmount);

        vm.stopPrank();

        assertEq(fei.balanceOf(address(this)), withdrawAmount);
    }

    function testGuardianWithdrawAllToSafeAddress() public {
        vm.startPrank(MainnetAddresses.GUARDIAN);

        assertEq(fei.balanceOf(address(this)), 0);
        uint256 amountToWithdraw = pcvDeposit.balance();

        pcvGuardian.withdrawAllToSafeAddress(address(pcvDeposit));
        vm.stopPrank();

        assertEq(fei.balanceOf(address(this)), amountToWithdraw);
    }

    function testGuardWithdrawToSafeAddress() public {
        vm.startPrank(guard);
        assertEq(fei.balanceOf(address(this)), 0);
        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), withdrawAmount);

        assertEq(fei.balanceOf(address(this)), withdrawAmount);
    }

    function testGuardWithdrawAllToSafeAddress() public {
        vm.startPrank(guard);

        assertEq(fei.balanceOf(address(this)), 0);
        uint256 amountToWithdraw = pcvDeposit.balance();

        pcvGuardian.withdrawAllToSafeAddress(address(pcvDeposit));
        vm.stopPrank();

        assertEq(fei.balanceOf(address(this)), amountToWithdraw);
    }

    function testWithdrawToSafeAddressFailWhenNoRole() public {
        vm.expectRevert(bytes("UNAUTHORIZED"));
        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), withdrawAmount);
    }

    function testWithdrawAllToSafeAddressFailWhenNoRole() public {
        vm.expectRevert(bytes("UNAUTHORIZED"));
        pcvGuardian.withdrawAllToSafeAddress(address(pcvDeposit));
    }

    function testWithdrawToSafeAddressFailWhenNotWhitelist() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        vm.expectRevert(
            bytes("PCVGuardian: Provided address is not whitelisted")
        );

        pcvGuardian.withdrawToSafeAddress(address(0x1), withdrawAmount);
    }

    function testWithdrawAllToSafeAddressFailWhenNotWhitelist() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        vm.expectRevert(
            bytes("PCVGuardian: Provided address is not whitelisted")
        );

        pcvGuardian.withdrawAllToSafeAddress(address(0x1));
    }

    function testWithdrawToSafeAddressFailWhenGuardRevokedGovernor() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        pcvGuardAdmin.revokePCVGuardRole(guard);

        vm.prank(guard);
        vm.expectRevert(bytes("UNAUTHORIZED"));

        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), withdrawAmount);
    }

    function testWithdrawAllToSafeAddressFailWhenGuardRevokedGovernor() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        pcvGuardAdmin.revokePCVGuardRole(guard);

        vm.prank(guard);
        vm.expectRevert(bytes("UNAUTHORIZED"));

        pcvGuardian.withdrawAllToSafeAddress(address(pcvDeposit));
    }

    function testWithdrawToSafeAddressFailWhenGuardRevokedGuardian() public {
        vm.prank(MainnetAddresses.GUARDIAN);
        pcvGuardAdmin.revokePCVGuardRole(guard);

        vm.prank(guard);
        vm.expectRevert(bytes("UNAUTHORIZED"));

        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), withdrawAmount);
    }

    function testWithdrawAllToSafeAddressFailWhenGuardRevokedGuardian() public {
        vm.prank(MainnetAddresses.GUARDIAN);
        pcvGuardAdmin.revokePCVGuardRole(guard);

        vm.prank(guard);
        vm.expectRevert(bytes("UNAUTHORIZED"));

        pcvGuardian.withdrawAllToSafeAddress(address(pcvDeposit));
    }

    function testSetWhiteListAddress() public {
        vm.prank(MainnetAddresses.GOVERNOR);

        pcvGuardian.addWhitelistAddress(address(0x123));
        assertTrue(pcvGuardian.isWhitelistAddress(address(0x123)));
    }

    function testUnsetWhiteListAddress() public {
        vm.prank(MainnetAddresses.GOVERNOR);

        pcvGuardian.removeWhitelistAddress(address(pcvDeposit));
        assertTrue(!pcvGuardian.isWhitelistAddress(address(pcvDeposit)));
    }
}
