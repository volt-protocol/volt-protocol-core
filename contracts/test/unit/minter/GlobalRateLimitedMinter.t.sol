// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Test} from "forge-std/Test.sol";
import {ICoreV2} from "../../../core/ICoreV2.sol";
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

    ICoreV2 private core;
    GlobalRateLimitedMinter public grlm;
    address private coreAddress;
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

        vm.startPrank(addresses.governorAddress);

        core.grantMinter(address(grlm));

        core.grantRateLimitedMinter(guardianAddresses.pcvGuardAddress1);
        core.grantRateLimitedMinter(guardianAddresses.pcvGuardAddress2);

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

    function testMintAsMinterSucceeds(uint80 mintAmount) public {
        uint256 startingBuffer = grlm.buffer();

        vm.prank(guardianAddresses.pcvGuardAddress1);
        grlm.mintVolt(address(this), mintAmount);
        uint256 endingBuffer = grlm.buffer();

        assertEq(volt.balanceOf(address(this)), mintAmount);
        assertEq(endingBuffer, startingBuffer - mintAmount);
    }
}
