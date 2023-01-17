// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IVolt} from "../../volt/Volt.sol";
import {Volt} from "../../volt/Volt.sol";
import {ICore} from "../../core/ICore.sol";
import {Core} from "../../core/Core.sol";
import {Vm} from "@forge-std/Vm.sol";
import {Test} from "@forge-std/Test.sol";
import {getCore} from "./utils/Fixtures.sol";
import {TestAddresses as addresses} from "./utils/TestAddresses.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract UnitTestVolt is Test {
    IVolt private volt;
    ICore private core;

    function setUp() public {
        core = getCore();

        volt = core.volt();
    }

    function testDeployedMetaData() public {
        assertEq(volt.totalSupply(), 0);
        assertTrue(core.isGovernor(addresses.governorAddress));
    }

    function testMintsVolt() public {
        uint256 mintAmount = 100;

        vm.prank(addresses.minterAddress);
        volt.mint(addresses.userAddress, mintAmount);

        assertEq(volt.balanceOf(addresses.userAddress), mintAmount);
    }
}
