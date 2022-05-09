// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {PCVGuardian} from "../../pcv/PCVGuardian.sol";
import {PCVGuardAdmin} from "../../pcv/PCVGuardAdmin.sol";

import {TribeRoles} from "../../core/TribeRoles.sol";
import {ICore} from "../../core/ICore.sol";
import {IVolt} from "../../volt/Volt.sol";
import {IPCVDeposit} from "../../pcv/IPCVDeposit.sol";
import {getMainnetAddresses, FeiTestAddresses} from "../unit/utils/Fixtures.sol";
import {DSTest} from "../unit/utils/DSTest.sol";
import {Vm} from "../unit/utils/Vm.sol";

contract IntegrationTestPCVGuardian is DSTest {
    PCVGuardian private pcvGuardian;
    PCVGuardAdmin private pcvGuardAdmin;

    ICore private core = ICore(0xEC7AD284f7Ad256b64c6E69b84Eb0F48f42e8196);
    IVolt private fei = IVolt(0x956F47F50A910163D8BF957Cf5846D573E7f87CA);

    IPCVDeposit private pcvDeposit =
        IPCVDeposit(0x4188fbD7aDC72853E3275F1c3503E170994888D7);

    Vm public constant vm = Vm(HEVM_ADDRESS);

    FeiTestAddresses public addresses = getMainnetAddresses();

    address[] public whitelistAddresses;
    address public guard = address(0x123456789);

    uint256 public withdrawAmount = 23_000e18; // approximate amount deposited at this block time

    function setUp() public {
        whitelistAddresses.push(address(pcvDeposit));

        pcvGuardian = new PCVGuardian(
            address(core),
            address(this), // using 'this' address as the safe address for withdrawals
            whitelistAddresses
        );

        pcvGuardAdmin = new PCVGuardAdmin(address(core));

        // grant the pcvGuardian the PCV controller and Guardian roles
        vm.startPrank(addresses.voltDeployerAddress);
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

    function testGovernorWithdrawToSafeAddress() public {
        vm.startPrank(addresses.voltDeployerAddress);
        assertEq(fei.balanceOf(address(this)), 0);

        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), withdrawAmount);

        assertEq(fei.balanceOf(address(this)), withdrawAmount);
    }

    function testGuardianWithdrawToSafeAddress() public {
        vm.prank(addresses.voltDeployerAddress);
        core.grantGuardian(address(0x1234));

        assertEq(fei.balanceOf(address(this)), 0);

        vm.prank(address(0x1234));
        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), withdrawAmount);

        assertEq(fei.balanceOf(address(this)), withdrawAmount);
    }

    function testGuardWithdrawToSafeAddress() public {
        vm.startPrank(guard);
        assertEq(fei.balanceOf(address(this)), 0);
        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), withdrawAmount);

        assertEq(fei.balanceOf(address(this)), withdrawAmount);
    }

    function testWithdrawToSafeAddressFailWhenNoRole() public {
        vm.expectRevert(bytes("UNAUTHORIZED"));
        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), withdrawAmount);
    }

    function testWithdrawToSafeAddressFailWhenNotWhitelist() public {
        vm.prank(addresses.voltDeployerAddress);
        vm.expectRevert(bytes("Provided address is not whitelisted"));

        pcvGuardian.withdrawToSafeAddress(address(0x1), withdrawAmount);
    }

    function testWithdrawToSafeAddressFailWhenGuardRevokedGovernor() public {
        vm.prank(addresses.voltDeployerAddress);
        pcvGuardAdmin.revokePCVGuardRole(guard);

        vm.prank(guard);
        vm.expectRevert(bytes("UNAUTHORIZED"));

        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), withdrawAmount);
    }

    function testWithdrawToSafeAddressFailWhenGuardRevokedGuardian() public {
        vm.prank(addresses.guardianAddress);
        pcvGuardAdmin.revokePCVGuardRole(guard);

        vm.prank(guard);
        vm.expectRevert(bytes("UNAUTHORIZED"));

        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), withdrawAmount);
    }

    function testSetWhiteListAddress() public {
        vm.prank(addresses.voltDeployerAddress);

        pcvGuardian.setWhitelistAddress(address(0x123));
        assertTrue(pcvGuardian.isWhitelistAddress(address(0x123)));
    }

    function testUnsetWhiteListAddress() public {
        vm.prank(addresses.voltDeployerAddress);

        pcvGuardian.unsetWhitelistAddress(address(pcvDeposit));
        assertTrue(!pcvGuardian.isWhitelistAddress(address(pcvDeposit)));
    }
}
