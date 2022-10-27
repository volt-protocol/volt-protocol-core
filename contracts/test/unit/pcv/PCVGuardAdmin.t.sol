// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {PCVGuardAdmin} from "../../../pcv/PCVGuardAdmin.sol";
import {getCore, getAddresses, VoltTestAddresses} from "./../utils/Fixtures.sol";
import {TribeRoles} from "../../../core/TribeRoles.sol";
import {ICore} from "../../../core/ICore.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {Vm} from "./../utils/Vm.sol";

contract UnitTestPCVGuardAdmin is DSTest {
    PCVGuardAdmin private pcvGuardAdmin;
    ICore private core;

    Vm public constant vm = Vm(HEVM_ADDRESS);
    VoltTestAddresses public addresses = getAddresses();

    address public guard = address(0x123456789);

    function setUp() public {
        core = getCore();

        pcvGuardAdmin = new PCVGuardAdmin(address(core));

        vm.startPrank(addresses.governorAddress);

        // create the PCV_GUARD_ADMIN role and grant it to the PCVGuardAdmin contract
        core.createRole(TribeRoles.PCV_GUARD_ADMIN, TribeRoles.GOVERNOR);
        core.grantRole(TribeRoles.PCV_GUARD_ADMIN, address(pcvGuardAdmin));

        // create the PCV guard role, and grant it to the 'guard' address
        core.createRole(TribeRoles.PCV_GUARD, TribeRoles.PCV_GUARD_ADMIN);
        pcvGuardAdmin.grantPCVGuardRole(guard);
        vm.stopPrank();
    }

    function testPCVGuardAdminRole() public {
        assertTrue(
            core.hasRole(TribeRoles.PCV_GUARD_ADMIN, address(pcvGuardAdmin))
        );
    }

    function testGrantPCVGuard() public {
        vm.prank(addresses.governorAddress);
        pcvGuardAdmin.grantPCVGuardRole(address(0x1234));

        assertTrue(core.hasRole(TribeRoles.PCV_GUARD, address(0x1234)));
    }

    function testGrantPCVGuardFailWhenNoRoles() public {
        vm.expectRevert(bytes("CoreRef: Caller is not a governor"));
        pcvGuardAdmin.grantPCVGuardRole(address(0x1234));
    }

    function testGrantPCVGuardFailWhenGuardian() public {
        vm.prank(addresses.guardianAddress);
        vm.expectRevert(bytes("CoreRef: Caller is not a governor"));
        pcvGuardAdmin.grantPCVGuardRole(address(0x1234));
    }

    function testRevokePCVGuardGovernor() public {
        vm.prank(addresses.governorAddress);
        pcvGuardAdmin.revokePCVGuardRole(guard);

        assertTrue(!core.hasRole(TribeRoles.PCV_GUARD, guard));
    }

    function testRevokePCVGuardGuardian() public {
        vm.prank(addresses.guardianAddress);
        pcvGuardAdmin.revokePCVGuardRole(guard);

        assertTrue(!core.hasRole(TribeRoles.PCV_GUARD, guard));
    }

    function testRevokePCVGuardFailWhenNoRole() public {
        vm.expectRevert(bytes("CoreRef: Caller is not a guardian or governor"));
        pcvGuardAdmin.revokePCVGuardRole(guard);
    }
}
