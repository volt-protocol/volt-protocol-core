// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Test} from "../../../../forge-std/src/Test.sol";
import {ICoreV2} from "../../../core/ICoreV2.sol";
import {MockMinter} from "../../../mock/MockMinter.sol";
import {IGRLM, GlobalRateLimitedMinter} from "../../../minter/GlobalRateLimitedMinter.sol";
import {getCoreV2, getAddresses, getVoltAddresses, VoltAddresses, VoltTestAddresses} from "./../utils/Fixtures.sol";

/// deployment steps
/// 1. core v2
/// 2. Global Rate Limited Minter

/// setup steps
/// 1. grant minter role to Global Rate Limited Minter
/// 2. grant global rate limited minter role to 2 EOA's

contract GlobalRateLimitedMinterUnitTest is Test {
    using SafeCast for *;

    VoltTestAddresses public addresses = getAddresses();
    VoltAddresses public guardianAddresses = getVoltAddresses();

    GlobalRateLimitedMinter public grlm;
    address private coreAddress;
    MockMinter private minter;
    ICoreV2 private core;
    IERC20 private volt;

    /// ---------- GRLM PARAMS ----------

    /// maximum rate limit per second is 100 VOLT
    uint256 public constant maxRateLimitPerSecondMinting = 100e18;

    /// replenish 500k VOLT per day
    uint128 public constant rateLimitPerSecondMinting = 5.787e18;

    /// buffer cap of 1.5m VOLT
    uint128 public constant bufferCapMinting = 1_500_000e18;

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

        vm.startPrank(addresses.governorAddress);

        core.grantMinter(address(grlm));
        core.grantLocker(address(grlm));

        core.grantRateLimitedMinter(guardianAddresses.pcvGuardAddress1);
        core.grantRateLimitedMinter(guardianAddresses.pcvGuardAddress2);
        core.grantRateLimitedRedeemer(guardianAddresses.pcvGuardAddress1);
        core.grantRateLimitedRedeemer(guardianAddresses.pcvGuardAddress2);

        core.grantRateLimitedMinter(address(minter));
        core.grantLocker(address(minter));

        core.setGlobalRateLimitedMinter(IGRLM(address(grlm)));

        vm.stopPrank();

        vm.label(address(grlm), "grlm");
        vm.label(address(core), "core");
        vm.label(address(this), "address this");
    }

    function testSetup() public {
        assertTrue(core.isMinter(address(grlm)));
        assertTrue(
            core.isRateLimitedMinter(guardianAddresses.pcvGuardAddress1)
        );
        assertTrue(
            core.isRateLimitedMinter(guardianAddresses.pcvGuardAddress2)
        );

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
        vm.expectRevert("CoreRef: restricted lock");
        vm.prank(guardianAddresses.pcvGuardAddress1);
        grlm.mintVolt(address(this), 0);
    }

    function testReplenishAsMinterFailsWhenNotLocked() public {
        vm.expectRevert("CoreRef: restricted lock");
        vm.prank(guardianAddresses.pcvGuardAddress1);
        grlm.replenishBuffer(0);
    }

    function testMintAsMinterSucceeds(uint80 mintAmount) public {
        uint256 startingBuffer = grlm.buffer();

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
        core.grantRateLimitedRedeemer(address(minter));

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
