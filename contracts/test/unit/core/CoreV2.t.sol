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
}
