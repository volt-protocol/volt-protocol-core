// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IVolt} from "../../../volt/Volt.sol";
import {Volt} from "../../../volt/Volt.sol";
import {ICore} from "../../../core/ICore.sol";
import {L2Core, Vcon} from "../../../core/L2Core.sol";
import {Vm} from "./../utils/Vm.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {getL2Core, getAddresses, FeiTestAddresses} from "./../utils/Fixtures.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {MockERC20} from "./../../../mock/MockERC20.sol";

contract L2CoreTest is DSTest {
    L2Core private core;

    Vm public constant vm = Vm(HEVM_ADDRESS);
    FeiTestAddresses public addresses = getAddresses();
    MockERC20 volt;
    Vcon vcon;

    function setUp() public {
        volt = new MockERC20();

        // Deploy Core from Governor address
        vm.startPrank(addresses.governorAddress);
        core = new L2Core(IVolt(address(volt)));
        vcon = new Vcon(addresses.governorAddress, addresses.governorAddress);
    }

    function testSetup() public {
        assertEq(address(core.volt()), address(volt));
        assertEq(address(core.vcon()), address(vcon));
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
