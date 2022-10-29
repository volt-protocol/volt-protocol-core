// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Vm} from "./../utils/Vm.sol";
import {Volt} from "../../../volt/Volt.sol";
import {IVolt} from "../../../volt/Volt.sol";
import {ICore} from "../../../core/ICore.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {VoltRoles} from "../../../core/VoltRoles.sol";
import {MockERC20} from "./../../../mock/MockERC20.sol";
import {CoreV2, Vcon} from "../../../core/CoreV2.sol";
import {getCoreV2, getAddresses, VoltTestAddresses} from "./../utils/Fixtures.sol";

contract UnitTestCoreV2 is DSTest {
    CoreV2 private core;

    Vm public constant vm = Vm(HEVM_ADDRESS);
    VoltTestAddresses public addresses = getAddresses();
    MockERC20 volt;
    Vcon vcon;

    function setUp() public {
        volt = new MockERC20();

        // Deploy Core from Governor address
        vm.prank(addresses.governorAddress);
        core = new CoreV2(address(volt));
        vcon = new Vcon(addresses.governorAddress, addresses.governorAddress);
    }

    function testSetup() public {
        assertEq(address(core.volt()), address(volt));
        assertEq(address(core.vcon()), address(0)); /// vcon starts set to address 0

        assertTrue(core.isGovernor(address(core))); /// core contract is governor
        assertTrue(core.isGovernor(addresses.governorAddress)); /// msg.sender of contract is governor
        assertTrue(!core.isGovernor(address(this))); /// only 2 governors

        bytes32 governRole = core.GOVERN_ROLE();
        /// assert all roles have the proper admin
        assertEq(core.getRoleAdmin(core.GOVERN_ROLE()), governRole);
        assertEq(core.getRoleAdmin(core.MINTER_ROLE()), governRole);
        assertEq(core.getRoleAdmin(core.GUARDIAN_ROLE()), governRole);
        assertEq(core.getRoleAdmin(core.PCV_CONTROLLER_ROLE()), governRole);
        assertEq(core.getRoleAdmin(core.SYSTEM_STATE_ROLE()), governRole);

        /// assert there is only 1 of each role
        assertEq(core.getRoleMemberCount(governRole), 2); /// msg.sender of contract and core is governor
        assertEq(core.getRoleMemberCount(core.MINTER_ROLE()), 0); /// this role has not been granted
        assertEq(core.getRoleMemberCount(core.GUARDIAN_ROLE()), 0); /// this role has not been granted
        assertEq(core.getRoleMemberCount(core.PCV_CONTROLLER_ROLE()), 0); /// this role has not been granted
        assertEq(core.getRoleMemberCount(core.SYSTEM_STATE_ROLE()), 0); /// this role has not been granted

        assertTrue(core.isUnlocked()); /// core starts out unlocked
        assertTrue(!core.isLocked()); /// core starts out not locked
    }

    /// CoreV2

    function testGovernorSetsVolt() public {
        vm.prank(addresses.governorAddress);
        core.setVolt(IVolt(address(addresses.userAddress)));

        assertEq(address(core.volt()), addresses.userAddress);
    }

    function testNonGovernorFailsSettingVolt() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.setVolt(IVolt(address(addresses.userAddress)));
    }

    function testGovernorSetsVcon() public {
        vm.prank(addresses.governorAddress);
        core.setVcon(IERC20(addresses.userAddress));

        assertEq(address(core.vcon()), addresses.userAddress);
    }

    function testNonGovernorFailsSettingVcon() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.setVcon(IERC20(addresses.userAddress));
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

    function testGovCreatesRole() public {
        uint256 role = 100;
        vm.prank(addresses.governorAddress);
        core.createRole(bytes32(role), VoltRoles.GOVERNOR);
        assertEq(core.getRoleAdmin(bytes32(role)), VoltRoles.GOVERNOR);
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
        core.grantState(address(this));
        assertTrue(core.isState(address(this)));
    }

    function testGovRevokesStateSucceeds() public {
        testGovAddsMinterSucceeds();
        vm.prank(addresses.governorAddress);
        core.revokeState(address(this));
        assertTrue(!core.isState(address(this)));
    }

    function testNonGovAddsStateFails() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.grantState(address(this));
    }

    function testNonGovRevokesStateFails() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.revokeState(address(this));
    }
}
