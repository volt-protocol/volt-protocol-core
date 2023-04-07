// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Test} from "@forge-std/Test.sol";
import {CoreV2} from "@voltprotocol/core/CoreV2.sol";
import {MockERC20} from "@test/mock/MockERC20.sol";
import {getCoreV2} from "@test/unit/utils/Fixtures.sol";
import {VoltRoles} from "@voltprotocol/core/VoltRoles.sol";
import {RateLimitedCreditMinter} from "@voltprotocol/rate-limits/RateLimitedCreditMinter.sol";
import {TestAddresses as addresses} from "@test/unit/utils/TestAddresses.sol";

contract RateLimitedCreditMinterUnitTest is Test {
    RateLimitedCreditMinter public rlcm;
    MockERC20 private token;
    CoreV2 private core;
    address constant alice = address(0x616c696365);

    uint256 MAX_RATE_LIMIT_PER_SECOND = 10 ether;
    uint128 RATE_LIMIT_PER_SECOND = 10 ether;
    uint128 BUFFER_CAP = 10_000_000 ether;

    function setUp() public {
        vm.warp(1679067867);
        vm.roll(16848497);
        core = getCoreV2();
        token = new MockERC20();
        rlcm = new RateLimitedCreditMinter(
            address(core),
            address(token),
            MAX_RATE_LIMIT_PER_SECOND,
            RATE_LIMIT_PER_SECOND,
            BUFFER_CAP
        );

        vm.label(address(token), "token");
        vm.label(address(core), "core");
        vm.label(address(rlcm), "rlcm");
        vm.label(address(this), "test");
    }

    function testInitialState() public {
        assertEq(address(rlcm.core()), address(core));
        assertEq(rlcm.token(), address(token));
    }

    function testMint() public {
        // without role, minting reverts
        vm.expectRevert("UNAUTHORIZED");
        rlcm.mint(address(this), 100);

        // create/grant role
        vm.startPrank(addresses.governorAddress);
        core.createRole(
            VoltRoles.RATE_LIMITED_CREDIT_MINTER,
            VoltRoles.GOVERNOR
        );
        core.grantRole(VoltRoles.RATE_LIMITED_CREDIT_MINTER, address(this));
        vm.stopPrank();

        // mint tokens for alice
        rlcm.mint(alice, 100);
        assertEq(token.balanceOf(alice), 100);
        assertEq(rlcm.buffer(), BUFFER_CAP - 100);
    }

    function testReplenishBuffer() public {
        // without role, replenishBuffer reverts
        vm.expectRevert("UNAUTHORIZED");
        rlcm.replenishBuffer(100);

        // create/grant role
        vm.startPrank(addresses.governorAddress);
        core.createRole(
            VoltRoles.RATE_LIMITED_CREDIT_MINTER,
            VoltRoles.GOVERNOR
        );
        core.grantRole(VoltRoles.RATE_LIMITED_CREDIT_MINTER, address(this));
        vm.stopPrank();

        // mint all the available buffer for alice
        rlcm.mint(alice, rlcm.buffer());
        assertEq(token.balanceOf(alice), BUFFER_CAP);

        // trying to mint more reverts
        vm.expectRevert("RateLimited: no rate limit buffer");
        rlcm.mint(alice, 100);

        // replenish buffer
        rlcm.replenishBuffer(100);
        assertEq(rlcm.buffer(), 100);

        // can mint the replenished amount
        rlcm.mint(alice, 100);
    }

    function testMintPausable() public {
        // create/grant role
        vm.startPrank(addresses.governorAddress);
        core.createRole(
            VoltRoles.RATE_LIMITED_CREDIT_MINTER,
            VoltRoles.GOVERNOR
        );
        core.grantRole(VoltRoles.RATE_LIMITED_CREDIT_MINTER, address(this));
        rlcm.pause();
        vm.stopPrank();

        // minting reverts because the contract is paused
        vm.expectRevert("Pausable: paused");
        rlcm.mint(alice, 100);
    }

    function testReplenishBufferPausable() public {
        // create/grant role
        vm.startPrank(addresses.governorAddress);
        core.createRole(
            VoltRoles.RATE_LIMITED_CREDIT_MINTER,
            VoltRoles.GOVERNOR
        );
        core.grantRole(VoltRoles.RATE_LIMITED_CREDIT_MINTER, address(this));
        rlcm.pause();
        vm.stopPrank();

        // replenishBuffer reverts because the contract is paused
        vm.expectRevert("Pausable: paused");
        rlcm.replenishBuffer(100);
    }
}
