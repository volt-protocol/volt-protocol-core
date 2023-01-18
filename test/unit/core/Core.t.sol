// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Vm} from "@forge-std/Vm.sol";
import {Test} from "@forge-std/Test.sol";
import {Volt} from "@voltprotocol/v1/Volt.sol";
import {Core} from "@voltprotocol/v1/Core.sol";
import {IVolt} from "@voltprotocol/v1/Volt.sol";
import {ICore} from "@voltprotocol/v1/ICore.sol";
import {Test} from "@forge-std/Test.sol";
import {TestAddresses as addresses} from "@test/unit/utils/TestAddresses.sol";
import {getCore} from "@test/unit/utils/Fixtures.sol";

contract UnitTestCore is Test {
    IVolt private volt;
    Core private core;

    function setUp() public {
        core = getCore();

        volt = core.volt();
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
