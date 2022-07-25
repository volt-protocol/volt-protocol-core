// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IVolt} from "../../../volt/Volt.sol";
import {Volt} from "../../../volt/Volt.sol";
import {ICore} from "../../../core/ICore.sol";
import {L2Core, Vcon} from "../../../core/L2Core.sol";
import {Vm} from "./../utils/Vm.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {getL2Core, getAddresses, VoltTestAddresses} from "./../utils/Fixtures.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {MockERC20} from "./../../../mock/MockERC20.sol";

contract UnitTestL2Core is DSTest {
    L2Core private core;

    Vm public constant vm = Vm(HEVM_ADDRESS);
    VoltTestAddresses public addresses = getAddresses();
    MockERC20 volt;
    Vcon vcon;

    function setUp() public {
        volt = new MockERC20();

        // Deploy Core from Governor address
        vm.prank(addresses.governorAddress);
        core = new L2Core(IVolt(address(volt)));
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
        assertEq(core.getRoleAdmin(core.BURNER_ROLE()), governRole);
        assertEq(core.getRoleAdmin(core.MINTER_ROLE()), governRole);
        assertEq(core.getRoleAdmin(core.GUARDIAN_ROLE()), governRole);
        assertEq(core.getRoleAdmin(core.PCV_CONTROLLER_ROLE()), governRole);

        /// assert there is only 1 of each role
        assertEq(core.getRoleMemberCount(governRole), 2); /// msg.sender of contract and core is governor
        assertEq(core.getRoleMemberCount(core.BURNER_ROLE()), 0); /// this role has not been granted
        assertEq(core.getRoleMemberCount(core.MINTER_ROLE()), 0); /// this role has not been granted
        assertEq(core.getRoleMemberCount(core.GUARDIAN_ROLE()), 0); /// this role has not been granted
        assertEq(core.getRoleMemberCount(core.PCV_CONTROLLER_ROLE()), 0); /// this role has not been granted
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
