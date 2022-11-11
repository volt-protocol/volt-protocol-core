// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Vm} from "./../utils/Vm.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {CoreV2} from "../../../core/CoreV2.sol";
import {VoltRoles} from "../../../core/VoltRoles.sol";
import {getCoreV2, getAddresses, VoltTestAddresses} from "./../utils/Fixtures.sol";

contract UnitTestPermissionsV2 is DSTest {
    CoreV2 private core;

    Vm public constant vm = Vm(HEVM_ADDRESS);
    VoltTestAddresses public addresses = getAddresses();

    function setUp() public {
        core = getCoreV2();
    }

    function testSetup() public {
        assertTrue(core.isGovernor(address(core))); /// core contract is governor
        assertTrue(core.isGovernor(addresses.governorAddress)); /// msg.sender of contract is governor
        assertTrue(!core.isGovernor(address(this))); /// only 2 governors

        bytes32 governRole = core.GOVERN_ROLE();
        /// assert all roles have the proper admin
        assertEq(core.getRoleAdmin(core.GOVERN_ROLE()), governRole);
        assertEq(core.getRoleAdmin(core.MINTER_ROLE()), governRole);
        assertEq(core.getRoleAdmin(core.GUARDIAN_ROLE()), governRole);
        assertEq(core.getRoleAdmin(core.PCV_CONTROLLER_ROLE()), governRole);
        assertEq(core.getRoleAdmin(core.GLOBAL_LOCKER_ROLE()), governRole);
        assertEq(core.getRoleAdmin(core.PCV_GUARD_ROLE()), governRole);

        /// assert there is only 1 of each role
        assertEq(core.getRoleMemberCount(governRole), 2); /// msg.sender of contract and core is governor
        assertEq(core.getRoleMemberCount(core.MINTER_ROLE()), 1); /// this role has not been granted
        assertEq(core.getRoleMemberCount(core.GUARDIAN_ROLE()), 1); /// this role has not been granted
        assertEq(core.getRoleMemberCount(core.PCV_CONTROLLER_ROLE()), 1); /// this role has not been granted
        assertEq(core.getRoleMemberCount(core.GLOBAL_LOCKER_ROLE()), 0); /// this role has not been granted
        assertEq(core.getRoleMemberCount(core.PCV_GUARD_ROLE()), 0); /// this role has not been granted

        /// core starts out unlocked and unused
        assertTrue(core.isUnlocked());
        assertTrue(!core.isLocked());
        assertEq(core.lastSender(), address(0));
    }

    /// PermissionsV2 Role acl tests

    function testRandomsCannotCreateRole(address sender, bytes32 role) public {
        vm.assume(!core.hasRole(VoltRoles.GOVERNOR, sender));

        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(sender), 20),
                " is missing role ",
                Strings.toHexString(uint256(core.getRoleAdmin(role)), 32)
            )
        );
        vm.prank(sender);
        core.grantRole(role, sender);
    }

    function testGovCreatesRoleSucceeds() public {
        uint256 role = 100;
        vm.prank(addresses.governorAddress);
        core.createRole(bytes32(role), VoltRoles.GOVERNOR);
        assertEq(core.getRoleAdmin(bytes32(role)), VoltRoles.GOVERNOR);
    }

    function testNonGovCreatesRoleFails() public {
        uint256 role = 100;
        vm.expectRevert("Permissions: Caller is not a governor");
        core.createRole(bytes32(role), VoltRoles.GOVERNOR);
    }

    function testNonGuardianRevokeOverrideFails() public {
        vm.expectRevert("Permissions: Caller is not a guardian");
        core.revokeOverride(VoltRoles.GOVERNOR, addresses.governorAddress);
    }

    function testGuardianRevokeOverrideGovernorFails() public {
        vm.expectRevert("Permissions: Guardian cannot revoke governor");
        vm.prank(addresses.guardianAddress);
        core.revokeOverride(VoltRoles.GOVERNOR, addresses.governorAddress);
    }

    function testGuardianRevokeOverrideStateSucceeds() public {
        vm.prank(addresses.governorAddress);
        core.grantGlobalLocker(address(this));
        assertTrue(core.isGlobalLocker(address(this)));

        vm.prank(addresses.guardianAddress);
        core.revokeOverride(VoltRoles.GLOBAL_LOCKER_ROLE, address(this));
        assertTrue(!core.isGlobalLocker(address(this)));
    }

    function testGovAddsPCVControllerSucceeds() public {
        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(this));
        assertTrue(core.isPCVController(address(this)));
    }

    function testGovRevokesPCVControllerSucceeds() public {
        testGovAddsPCVControllerSucceeds();
        assertTrue(core.isPCVController(address(this)));

        vm.prank(addresses.governorAddress);
        core.revokePCVController(address(this));
        assertTrue(!core.isPCVController(address(this)));
    }

    function testNonGovAddsPCVControllerFails() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.grantPCVController(address(this));
    }

    function testNonGovRevokesPCVControllerFails() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.revokePCVController(address(this));
    }

    function testGovAddsGovernorSucceeds() public {
        vm.prank(addresses.governorAddress);
        core.grantGovernor(address(this));
        assertTrue(core.isGovernor(address(this)));
    }

    function testGovRevokesGovernorSucceeds() public {
        vm.prank(addresses.governorAddress);
        core.revokeGovernor(address(this));
        assertTrue(!core.isGovernor(address(this)));
    }

    function testNonGovAddsGovernorFails() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.grantGovernor(address(this));
    }

    function testNonGovRevokesGovernorFails() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.revokeGovernor(address(this));
    }

    function testGovAddsPcvGuardSucceeds() public {
        vm.prank(addresses.governorAddress);
        core.grantPCVGuard(address(this));
        assertTrue(core.isPCVGuard(address(this)));
    }

    function testGovRevokesPcvGuard() public {
        testGovAddsGuardianSucceeds();
        vm.prank(addresses.governorAddress);
        core.revokePCVGuard(address(this));
        assertTrue(!core.isPCVGuard(address(this)));
    }

    function testNonGovAddsPcvGuardFails() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.grantPCVGuard(address(this));
    }

    function testNonGovRevokesPcvGuardFails() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.revokePCVGuard(address(this));
    }

    function testGovAddsGuardianSucceeds() public {
        vm.prank(addresses.governorAddress);
        core.grantGuardian(address(this));
        assertTrue(core.isGuardian(address(this)));
    }

    function testGovRevokesGuardianSucceeds() public {
        testGovAddsGuardianSucceeds();
        vm.prank(addresses.governorAddress);
        core.revokeGuardian(address(this));
        assertTrue(!core.isGuardian(address(this)));
    }

    function testNonGovAddsGuardianFails() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.grantGuardian(address(this));
    }

    function testNonGovRevokesGuardianFails() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.revokeGuardian(address(this));
    }

    function testGovAddsMinterSucceeds() public {
        vm.prank(addresses.governorAddress);
        core.grantMinter(address(this));
        assertTrue(core.isMinter(address(this)));
    }

    function testGovRevokesMinterSucceeds() public {
        testGovAddsMinterSucceeds();
        vm.prank(addresses.governorAddress);
        core.revokeMinter(address(this));
        assertTrue(!core.isMinter(address(this)));
    }

    function testNonGovAddsMinterFails() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.grantMinter(address(this));
    }

    function testNonGovRevokesMinterFails() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.revokeMinter(address(this));
    }

    function testGovAddsStateSucceeds() public {
        vm.prank(addresses.governorAddress);
        core.grantGlobalLocker(address(this));
        assertTrue(core.isGlobalLocker(address(this)));
    }

    function testGovRevokesStateSucceeds() public {
        testGovAddsMinterSucceeds();
        vm.prank(addresses.governorAddress);
        core.revokeGlobalLocker(address(this));
        assertTrue(!core.isGlobalLocker(address(this)));
    }

    function testNonGovAddsStateFails() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.grantGlobalLocker(address(this));
    }

    function testNonGovRevokesStateFails() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.revokeGlobalLocker(address(this));
    }

    function testGovAddsMinterRoleSucceeds() public {
        vm.prank(addresses.governorAddress);
        core.grantRateLimitedMinter(address(this));
        assertTrue(core.isRateLimitedMinter(address(this)));
    }

    function testGovRevokesMinterRoleSucceeds() public {
        testGovAddsMinterRoleSucceeds();
        vm.prank(addresses.governorAddress);
        core.revokeRateLimitedMinter(address(this));
        assertTrue(!core.isRateLimitedMinter(address(this)));
    }

    function testNonGovAddsMinterRoleFails() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.grantRateLimitedMinter(address(this));
    }

    function testNonGovRevokesMinterRoleFails() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.revokeRateLimitedMinter(address(this));
    }
}
