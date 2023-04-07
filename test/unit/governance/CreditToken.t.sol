// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Test} from "@forge-std/Test.sol";
import {CoreV2} from "@voltprotocol/core/CoreV2.sol";
import {getCoreV2} from "@test/unit/utils/Fixtures.sol";
import {VoltRoles} from "@voltprotocol/core/VoltRoles.sol";
import {CreditToken} from "@voltprotocol/governance/CreditToken.sol";
import {TestAddresses as addresses} from "@test/unit/utils/TestAddresses.sol";

contract CreditTokenUnitTest is Test {
    CoreV2 private core;
    CreditToken token;
    address constant alice = address(0x616c696365);
    address constant bob = address(0xB0B);

    function setUp() public {
        vm.warp(1679067867);
        vm.roll(16848497);
        core = CoreV2(address(getCoreV2()));
        token = new CreditToken(address(core));

        // labels
        vm.label(address(core), "core");
        vm.label(address(token), "token");
        vm.label(alice, "alice");
        vm.label(bob, "bob");
    }

    function testInitialState() public {
        assertEq(address(token.core()), address(core));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), 0);
    }

    function testMintAccessControl() public {
        // without role, mint reverts
        vm.expectRevert("UNAUTHORIZED");
        token.mint(alice, 100);

        // create/grant role
        vm.startPrank(addresses.governorAddress);
        core.createRole(VoltRoles.CREDIT_MINTER, VoltRoles.GOVERNOR);
        core.grantRole(VoltRoles.CREDIT_MINTER, address(this));
        vm.stopPrank();

        // mint tokens for alice
        token.mint(alice, 100);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), 100);

        // alice transfers to bob
        vm.prank(alice);
        token.transfer(bob, 100);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 100);
        assertEq(token.totalSupply(), 100);
    }
}
