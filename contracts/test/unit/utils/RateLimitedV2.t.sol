pragma solidity =0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Vm} from "./Vm.sol";
import {ICore} from "../../../core/ICore.sol";
import {DSTest} from "./DSTest.sol";
import {PCVDeposit} from "../../../pcv/PCVDeposit.sol";
import {TribeRoles} from "../../../core/TribeRoles.sol";
import {PCVGuardAdmin} from "../../../pcv/PCVGuardAdmin.sol";
import {ERC20Allocator} from "../../../pcv/utils/ERC20Allocator.sol";
import {MockRateLimitedV2} from "../../../mock/MockRateLimitedV2.sol";
import {ERC20HoldingPCVDeposit} from "../../../pcv/ERC20HoldingPCVDeposit.sol";
import {getCore, getAddresses, VoltTestAddresses} from "./Fixtures.sol";

import "hardhat/console.sol";

contract UnitTestRateLimitedV2 is DSTest {
    using SafeCast for *;

    /// @notice event emitted when buffer cap is updated
    event BufferCapUpdate(uint256 oldBufferCap, uint256 newBufferCap);

    /// @notice event emitted when rate limit per second is updated
    event RateLimitPerSecondUpdate(
        uint256 oldRateLimitPerSecond,
        uint256 newRateLimitPerSecond
    );

    /// @notice event emitted when buffer gets eaten into
    event BufferUsed(uint256 amountUsed, uint256 bufferRemaining);

    /// @notice event emitted when buffer gets replenished
    event BufferReplenished(uint256 amountReplenished, uint256 bufferRemaining);

    /// @notice foundry vm
    Vm public constant vm = Vm(HEVM_ADDRESS);

    /// @notice test addresses
    VoltTestAddresses public addresses = getAddresses();

    /// @notice rate limited v2 contract
    MockRateLimitedV2 rlm;

    /// @notice reference to core
    ICore private core;

    /// @notice maximum rate limit per second in RateLimitedV2
    uint256 private constant maxRateLimitPerSecond = 1_000_000e18;

    /// @notice rate limit per second in RateLimitedV2
    uint128 private constant rateLimitPerSecond = 10_000e18;

    /// @notice buffer cap in RateLimitedV2
    uint128 private constant bufferCap = 10_000_000e18;

    function setUp() public {
        core = getCore();
        rlm = new MockRateLimitedV2(
            address(core),
            maxRateLimitPerSecond,
            rateLimitPerSecond,
            bufferCap
        );
    }

    function testSetup() public {
        assertEq(rlm.bufferCap(), bufferCap);
        assertEq(rlm.rateLimitPerSecond(), rateLimitPerSecond);
        assertEq(rlm.MAX_RATE_LIMIT_PER_SECOND(), maxRateLimitPerSecond);
        assertEq(rlm.buffer(), bufferCap); /// buffer has not been depleted
    }

    /// ACL Tests

    function testSetBufferCapNonGovFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        rlm.setBufferCap(0);
    }

    function testSetBufferCapGovSucceeds() public {
        uint256 newBufferCap = 100_000e18;

        vm.prank(addresses.governorAddress);
        vm.expectEmit(true, false, false, true, address(rlm));
        emit BufferCapUpdate(bufferCap, newBufferCap);
        rlm.setBufferCap(newBufferCap.toUint128());

        assertEq(rlm.bufferCap(), newBufferCap);
        assertEq(rlm.buffer(), newBufferCap); /// buffer has not been depleted
    }

    function testSetRateLimitPerSecondNonGovFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        rlm.setRateLimitPerSecond(0);
    }

    function testSetRateLimitPerSecondGovSucceeds() public {
        uint256 newRateLimitPerSecond = 15_000e18;

        vm.prank(addresses.governorAddress);
        vm.expectEmit(true, false, false, true, address(rlm));
        emit RateLimitPerSecondUpdate(
            rateLimitPerSecond,
            newRateLimitPerSecond
        );
        rlm.setRateLimitPerSecond(newRateLimitPerSecond.toUint128());

        assertEq(rlm.rateLimitPerSecond(), newRateLimitPerSecond);
    }

    function testDepleteBuffer(uint128 amountToPull, uint16 warpAmount) public {
        if (amountToPull > bufferCap) {
            vm.expectRevert("RateLimited: rate limit hit");
            rlm.depleteBuffer(amountToPull);
        } else {
            vm.expectEmit(true, false, false, true, address(rlm));
            emit BufferUsed(amountToPull, bufferCap - amountToPull);
            rlm.depleteBuffer(amountToPull);
            uint256 endingBuffer = rlm.buffer();
            assertEq(endingBuffer, bufferCap - amountToPull);
            assertEq(block.timestamp, rlm.lastBufferUsedTime());

            vm.warp(block.timestamp + warpAmount);

            uint256 accruedBuffer = warpAmount * rateLimitPerSecond;
            uint256 expectedBuffer = Math.min(
                endingBuffer + accruedBuffer,
                bufferCap
            );
            assertEq(expectedBuffer, rlm.buffer());
        }
    }

    function testReplenishBuffer(uint128 amountToReplenish, uint16 warpAmount)
        public
    {
        rlm.depleteBuffer(bufferCap); /// fully exhaust buffer
        assertEq(rlm.buffer(), 0);

        uint256 actualAmountToReplenish = Math.min(
            amountToReplenish,
            bufferCap
        );
        vm.expectEmit(true, false, false, true, address(rlm));
        emit BufferReplenished(amountToReplenish, actualAmountToReplenish);

        rlm.replenishBuffer(amountToReplenish);
        assertEq(rlm.buffer(), actualAmountToReplenish);
        assertEq(block.timestamp, rlm.lastBufferUsedTime());

        vm.warp(block.timestamp + warpAmount);

        uint256 accruedBuffer = warpAmount * rateLimitPerSecond;
        uint256 expectedBuffer = Math.min(
            amountToReplenish + accruedBuffer,
            bufferCap
        );
        assertEq(expectedBuffer, rlm.buffer());
    }

    function testReplenishWhenAtBufferCapHasNoEffect(uint128 amountToReplenish)
        public
    {
        uint256 actualAmountToReplenish = 0;
        vm.expectEmit(true, false, false, true, address(rlm));
        emit BufferReplenished(amountToReplenish, actualAmountToReplenish);

        rlm.replenishBuffer(amountToReplenish);
        assertEq(rlm.buffer(), bufferCap);
        assertEq(block.timestamp, rlm.lastBufferUsedTime());
    }
}
