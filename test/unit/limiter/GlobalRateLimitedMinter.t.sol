// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Test} from "@forge-std/Test.sol";
import {ICoreV2} from "@voltprotocol/core/ICoreV2.sol";
import {MockMinter} from "@test/mock/MockMinter.sol";
import {IGlobalRateLimitedMinter, GlobalRateLimitedMinter} from "@voltprotocol/rate-limits/GlobalRateLimitedMinter.sol";
import {TestAddresses as addresses} from "@test/unit/utils/TestAddresses.sol";
import {getCoreV2, getVoltAddresses, VoltAddresses} from "@test/unit/utils/Fixtures.sol";
import {IGlobalReentrancyLock, GlobalReentrancyLock} from "@voltprotocol/core/GlobalReentrancyLock.sol";

/// deployment steps
/// 1. core v2
/// 2. Global Rate Limited Minter

/// setup steps
/// 1. grant minter role to Global Rate Limited Minter
/// 2. grant global rate limited minter role to 2 EOA's

contract GlobalRateLimitedMinterUnitTest is Test {
    using SafeCast for *;

    VoltAddresses public guardianAddresses = getVoltAddresses();

    GlobalRateLimitedMinter public grlm;
    IGlobalReentrancyLock private lock;
    address private coreAddress;
    MockMinter private minter;
    ICoreV2 private core;
    IERC20 private volt;

    /// ---------- GRLM PARAMS ----------

    /// maximum rate limit per second is 100 VOLT
    uint256 public constant maxRateLimitPerSecondMinting = 100e18;

    /// replenish 500k VOLT per day
    uint64 public constant rateLimitPerSecondMinting = 5.787e18;

    /// buffer cap of 1.5m VOLT
    uint96 public constant bufferCapMinting = 1_500_000e18;

    function setUp() public {
        vm.warp(1); /// warp past 0
        core = getCoreV2();
        coreAddress = address(core);
        volt = core.volt();
        grlm = new GlobalRateLimitedMinter(
            coreAddress,
            maxRateLimitPerSecondMinting,
            rateLimitPerSecondMinting,
            bufferCapMinting
        );
        minter = new MockMinter(coreAddress, address(grlm));
        lock = IGlobalReentrancyLock(
            address(new GlobalReentrancyLock(address(core)))
        );

        vm.startPrank(addresses.governorAddress);

        core.grantMinter(address(grlm));
        core.grantLocker(address(grlm));

        core.grantPsmMinter(guardianAddresses.pcvGuardAddress1);
        core.grantPsmMinter(guardianAddresses.pcvGuardAddress2);
        core.grantPsmMinter(address(minter));

        core.grantLocker(address(minter));

        core.setGlobalRateLimitedMinter(
            IGlobalRateLimitedMinter(address(grlm))
        );
        core.setGlobalReentrancyLock(lock);

        vm.stopPrank();

        vm.label(address(grlm), "grlm");
        vm.label(address(core), "core");
        vm.label(address(this), "address this");
    }

    function testSetup() public {
        assertTrue(core.isMinter(address(grlm)));
        assertTrue(core.isPsmMinter(guardianAddresses.pcvGuardAddress1));
        assertTrue(core.isPsmMinter(guardianAddresses.pcvGuardAddress2));

        assertEq(address(core.globalRateLimitedMinter()), address(grlm));
    }

    function testMintNonMinterFails() public {
        vm.expectRevert("UNAUTHORIZED");
        grlm.mintVolt(address(this), 100);
    }

    function testReplenishNonRedeemerFails() public {
        vm.expectRevert("UNAUTHORIZED");
        grlm.replenishBuffer(100);
    }

    function testMintAsMinterFailsWhenNotLocked() public {
        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        vm.prank(guardianAddresses.pcvGuardAddress1);
        grlm.mintVolt(address(this), 0);
    }

    function testReplenishAsMinterFailsWhenNotLocked() public {
        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        vm.prank(guardianAddresses.pcvGuardAddress1);
        grlm.replenishBuffer(0);
    }

    function testMintAsMinterSucceeds(uint80 mintAmount) public {
        uint256 startingBuffer = grlm.buffer();
        mintAmount = uint80(Math.min(mintAmount, grlm.midPoint())); /// avoid buffer overflow

        minter.mint(address(this), mintAmount);
        uint256 endingBuffer = grlm.buffer();

        assertEq(volt.balanceOf(address(this)), mintAmount);
        assertEq(endingBuffer, startingBuffer - mintAmount);
    }

    function testReplenishAsMinterSucceeds(
        uint80 replenishAmount,
        uint80 depleteAmount
    ) public {
        vm.prank(addresses.governorAddress);
        core.grantPsmMinter(address(minter));

        /// bound inputs to avoid rate limit over or under flows which would cause a revert
        depleteAmount = uint80(Math.min(depleteAmount, grlm.midPoint()));
        replenishAmount = uint80(
            Math.min(replenishAmount, grlm.buffer() - depleteAmount)
        );

        minter.mint(address(this), depleteAmount);

        uint256 startingBuffer = grlm.buffer();

        minter.replenishBuffer(replenishAmount);
        uint256 endingBuffer = grlm.buffer();

        assertEq(
            endingBuffer,
            Math.min(startingBuffer + replenishAmount, grlm.bufferCap())
        );
    }
}
