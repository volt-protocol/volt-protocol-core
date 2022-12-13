// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Test} from "../../../../forge-std/src/Test.sol";
import {CoreV2} from "../../../core/CoreV2.sol";
import {TestAddresses} from "./../utils/TestAddresses.sol";
import {TestAddresses as addresses} from "../utils/TestAddresses.sol";
import {IGlobalSystemExitRateLimiter, GlobalSystemExitRateLimiter} from "../../../limiter/GlobalSystemExitRateLimiter.sol";
import {getCoreV2, getVoltAddresses, VoltAddresses} from "./../utils/Fixtures.sol";
import {IGlobalReentrancyLock, GlobalReentrancyLock} from "../../../core/GlobalReentrancyLock.sol";

/// deployment steps
/// 1. core v2
/// 2. Global Rate Limited Minter

/// setup steps
/// 1. grant minter role to Global Rate Limited Minter
/// 2. grant global rate limited minter role to 2 EOA's

contract GlobalSystemExitRateLimiterUnitTest is Test {
    using SafeCast for *;

    VoltAddresses public guardianAddresses = getVoltAddresses();

    CoreV2 private core;
    IERC20 private volt;
    address private coreAddress;
    GlobalReentrancyLock public lock;
    GlobalSystemExitRateLimiter public gserl;

    /// ---------- GSERL PARAMS ----------

    /// maximum rate limit per second is 100 USD
    uint256 public constant maxRateLimitPerSecond = 100e18;

    /// replenish 500k USD per day
    uint128 public constant rateLimitPerSecond = 5.787e18;

    /// buffer cap of 1.5m USD
    uint128 public constant bufferCap = 1_500_000e18;

    function setUp() public {
        vm.warp(1); /// warp past 0
        core = getCoreV2();
        coreAddress = address(core);
        lock = new GlobalReentrancyLock(coreAddress);
        volt = core.volt();
        gserl = new GlobalSystemExitRateLimiter(
            coreAddress,
            maxRateLimitPerSecond,
            rateLimitPerSecond,
            bufferCap
        );

        vm.startPrank(addresses.governorAddress);

        core.setGlobalReentrancyLock(IGlobalReentrancyLock(address(lock)));

        core.grantLocker(address(this));
        core.grantLocker(address(gserl));

        core.grantRateLimitedMinter(guardianAddresses.pcvGuardAddress1);
        core.grantRateLimitedMinter(guardianAddresses.pcvGuardAddress2);
        core.grantRateLimitedRedeemer(guardianAddresses.pcvGuardAddress1);
        core.grantRateLimitedRedeemer(guardianAddresses.pcvGuardAddress2);

        core.setGlobalSystemExitRateLimiter(
            IGlobalSystemExitRateLimiter(address(gserl))
        );

        vm.stopPrank();

        vm.label(address(gserl), "gserl");
        vm.label(address(core), "core");
        vm.label(address(this), "address this");
    }

    function testSetup() public {
        assertEq(gserl.buffer(), bufferCap);
        assertEq(gserl.rateLimitPerSecond(), rateLimitPerSecond);
        assertEq(gserl.MAX_RATE_LIMIT_PER_SECOND(), maxRateLimitPerSecond);

        assertTrue(core.isLocker(address(gserl)));
        assertTrue(
            core.isRateLimitedMinter(guardianAddresses.pcvGuardAddress1)
        );
        assertTrue(
            core.isRateLimitedMinter(guardianAddresses.pcvGuardAddress2)
        );

        assertEq(address(core.globalSystemExitRateLimiter()), address(gserl));
    }

    function testDepleteBufferNonDepleterFails() public {
        vm.expectRevert("UNAUTHORIZED");
        gserl.depleteBuffer(100);
    }

    function testReplenishBufferNonDepleterFails() public {
        vm.expectRevert("UNAUTHORIZED");
        gserl.replenishBuffer(100);
    }

    function testReplenishAsReplenisherFailsWhenNotLocked() public {
        vm.prank(TestAddresses.governorAddress);
        core.grantSystemExitRateLimitReplenisher(address(this));

        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        gserl.replenishBuffer(0);
    }

    function testDepleteAsDepleterFailsWhenNotLocked() public {
        vm.prank(TestAddresses.governorAddress);
        core.grantSystemExitRateLimitDepleter(address(this));

        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        gserl.depleteBuffer(0);
    }

    function testDepleteAsDepleterSucceeds(uint80 amount) public {
        vm.prank(TestAddresses.governorAddress);
        core.grantSystemExitRateLimitDepleter(address(this));

        uint256 startingBuffer = gserl.buffer();

        lock.lock(1);
        gserl.depleteBuffer(amount);

        uint256 endingBuffer = gserl.buffer();

        assertEq(endingBuffer, startingBuffer - amount);
    }

    function testReplenishAsReplenisherSucceeds(
        uint80 replenishAmount,
        uint80 depleteAmount
    ) public {
        testDepleteAsDepleterSucceeds(depleteAmount);

        vm.prank(addresses.governorAddress);
        core.grantSystemExitRateLimitReplenisher(address(this));

        uint256 startingBuffer = gserl.buffer();

        gserl.replenishBuffer(replenishAmount);

        uint256 endingBuffer = gserl.buffer();

        assertEq(
            endingBuffer,
            Math.min(startingBuffer + replenishAmount, gserl.bufferCap())
        );
    }
}
