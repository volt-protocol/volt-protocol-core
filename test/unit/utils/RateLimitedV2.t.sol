pragma solidity =0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {console} from "@forge-std/console.sol";

import {Vm} from "@forge-std/Vm.sol";
import {Test} from "@forge-std/Test.sol";
import {ICoreV2} from "@voltprotocol/core/ICoreV2.sol";
import {PCVDeposit} from "@voltprotocol/pcv/PCVDeposit.sol";
import {VoltRoles} from "@voltprotocol/core/VoltRoles.sol";
import {MockRateLimitedV2} from "@test/mock/MockRateLimitedV2.sol";
import {ERC20HoldingPCVDeposit} from "@test/mock/ERC20HoldingPCVDeposit.sol";
import {TestAddresses as addresses} from "@test/unit/utils/TestAddresses.sol";
import {getCoreV2} from "@test/unit/utils/Fixtures.sol";

contract UnitTestRateLimitedV2 is Test {
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

    /// @notice rate limited v2 contract
    MockRateLimitedV2 rlm;

    /// @notice reference to core
    ICoreV2 private core;

    /// @notice maximum rate limit per second in RateLimitedV2
    uint256 private constant maxRateLimitPerSecond = 10e18;

    /// @notice rate limit per second in RateLimitedV2
    uint64 private constant rateLimitPerSecond = 10e18;

    /// @notice buffer cap in RateLimitedV2
    uint96 private constant bufferCap = 10_000_000e18;

    /// @notice mid point in RateLimitedV2
    uint96 private constant midPoint = bufferCap / 2;

    function setUp() public {
        core = getCoreV2();
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
        assertEq(rlm.buffer(), bufferCap / 2); /// buffer starts at midpoint
        assertEq(rlm.midPoint(), bufferCap / 2); /// mid point is buffercap / 2
        assertEq(rlm.buffer(), rlm.midPoint()); /// buffer starts at midpoint
    }

    /// ACL Tests

    function testSetBufferCapNonGovFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        rlm.setBufferCap(0);
    }

    function testSetBufferCapGovSucceeds() public {
        uint96 newBufferCap = 100_000e18;

        vm.prank(addresses.governorAddress);
        vm.expectEmit(true, false, false, true, address(rlm));
        emit BufferCapUpdate(bufferCap, newBufferCap);
        rlm.setBufferCap(newBufferCap);

        assertEq(rlm.bufferCap(), newBufferCap);
        assertEq(rlm.buffer(), bufferCap / 2); /// buffer starts at previous midpoint
    }

    function testSetRateLimitPerSecondNonGovFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        rlm.setRateLimitPerSecond(0);
    }

    function testSetRateLimitPerSecondAboveMaxFails() public {
        vm.expectRevert("RateLimited: rateLimitPerSecond too high");
        vm.prank(addresses.governorAddress);
        rlm.setRateLimitPerSecond(uint64(maxRateLimitPerSecond + 1));
    }

    function testSetRateLimitPerSecondSucceeds() public {
        vm.prank(addresses.governorAddress);
        rlm.setRateLimitPerSecond(uint64(maxRateLimitPerSecond));
        assertEq(rlm.rateLimitPerSecond(), maxRateLimitPerSecond);
    }

    function testDepleteBufferFailsWhenZeroBuffer() public {
        rlm.depleteBuffer(rlm.midPoint()); /// fully exhaust buffer
        vm.expectRevert("RateLimited: buffer cap underflow");
        rlm.depleteBuffer(bufferCap);
    }

    function testReplenishBufferFailsWhenAtBufferCap() public {
        rlm.buffer(); /// where are we at?
        rlm.replenishBuffer(rlm.midPoint()); /// completely fill buffer
        rlm.buffer(); /// where are we at?
        vm.expectRevert("RateLimited: buffer cap overflow");
        rlm.replenishBuffer(1);
    }

    function testSetRateLimitPerSecondGovSucceeds() public {
        uint256 newRateLimitPerSecond = rateLimitPerSecond - 1;

        vm.prank(addresses.governorAddress);
        vm.expectEmit(true, false, false, true, address(rlm));
        emit RateLimitPerSecondUpdate(
            rateLimitPerSecond,
            newRateLimitPerSecond
        );
        rlm.setRateLimitPerSecond(uint64(newRateLimitPerSecond));

        assertEq(rlm.rateLimitPerSecond(), newRateLimitPerSecond);
    }

    function testDepleteBuffer(uint128 amountToPull, uint16 warpAmount) public {
        if (amountToPull > bufferCap / 2) {
            vm.expectRevert("RateLimited: buffer cap underflow");
            rlm.depleteBuffer(amountToPull);
        } else {
            vm.expectEmit(true, false, false, true, address(rlm));
            emit BufferUsed(amountToPull, bufferCap / 2 - amountToPull);
            rlm.depleteBuffer(amountToPull);

            uint256 endingBuffer = rlm.buffer();
            assertEq(endingBuffer, bufferCap / 2 - amountToPull);
            assertEq(block.timestamp, rlm.lastBufferUsedTime());

            vm.warp(block.timestamp + warpAmount);

            uint256 accruedBuffer = uint256(warpAmount) *
                uint256(rateLimitPerSecond);
            uint256 expectedBuffer = Math.min( /// only accumulate to mid point after depletion
                endingBuffer + accruedBuffer,
                bufferCap / 2
            );
            assertEq(expectedBuffer, rlm.buffer());
        }
    }

    function testReplenishBuffer(
        uint128 amountToReplenish,
        uint16 warpAmount
    ) public {
        rlm.depleteBuffer(midPoint); /// fully exhaust buffer
        assertEq(rlm.buffer(), 0);

        uint256 actualAmountToReplenish = Math.min(amountToReplenish, midPoint);
        vm.expectEmit(true, false, false, true, address(rlm));
        emit BufferReplenished(
            actualAmountToReplenish,
            actualAmountToReplenish
        );

        rlm.replenishBuffer(actualAmountToReplenish);
        assertEq(rlm.buffer(), actualAmountToReplenish);
        assertEq(block.timestamp, rlm.lastBufferUsedTime());

        vm.warp(block.timestamp + warpAmount);

        uint256 cachedBufferStored = rlm.bufferStored();
        uint256 bufferDelta = rateLimitPerSecond * uint256(warpAmount);
        uint256 convergedAmount = _converge(cachedBufferStored, bufferDelta);

        assertEq(convergedAmount, rlm.buffer());
    }

    function testDepleteThenReplenishBuffer(
        uint128 amountToDeplete,
        uint128 amountToReplenish
    ) public {
        uint256 actualAmountToDeplete = Math.min(amountToDeplete, midPoint); /// bound input to less than or equal to the midPoint
        rlm.depleteBuffer(actualAmountToDeplete); /// deplete buffer
        assertEq(rlm.buffer(), midPoint - actualAmountToDeplete);

        /// either fill up the buffer, or partially refill
        uint256 actualAmountToReplenish = Math.min(
            amountToReplenish,
            bufferCap - rlm.buffer()
        );

        rlm.replenishBuffer(actualAmountToReplenish);
        uint256 finalState = midPoint -
            actualAmountToDeplete +
            actualAmountToReplenish;
        assertEq(rlm.buffer(), finalState);
        assertEq(block.timestamp, rlm.lastBufferUsedTime());

        vm.warp(block.timestamp + 500_000); /// 500k seconds * 10 Volt per second means the buffer should be back at the midpoint even if 0 replenishing occurred

        assertEq(rlm.buffer(), midPoint);
    }

    function testReplenishThenDepleteBuffer(
        uint128 amountToReplenish,
        uint128 amountToDeplete
    ) public {
        uint256 actualAmountToReplenish = Math.min(amountToReplenish, midPoint);
        rlm.replenishBuffer(actualAmountToReplenish);

        uint256 actualAmountToDeplete = Math.min(rlm.buffer(), amountToDeplete); /// bound input to less than or equal to the current buffer, another way to say this is bufferCap - actualAmountToReplenish

        rlm.depleteBuffer(actualAmountToDeplete); /// deplete buffer

        assertEq(rlm.buffer(), midPoint - actualAmountToDeplete);

        /// either fill up the buffer, or partially refill

        uint256 finalState = midPoint +
            actualAmountToReplenish -
            actualAmountToDeplete;

        assertEq(rlm.buffer(), finalState);
        assertEq(block.timestamp, rlm.lastBufferUsedTime());

        vm.warp(block.timestamp + 500_000); /// 500k seconds * 10 Volt per second means the buffer should be back at the midpoint even if 0 replenishing occurred

        assertEq(rlm.buffer(), midPoint);
    }

    function _converge(
        uint256 cachedBufferStored,
        uint256 bufferDelta
    ) private pure returns (uint256) {
        /// converge on mid point
        if (cachedBufferStored < midPoint) {
            /// buffer is below mid point, time accumulation can bring it back up to the mid point
            return Math.min(cachedBufferStored + bufferDelta, midPoint);
        } else if (cachedBufferStored > midPoint) {
            /// buffer is above the mid point, time accumulation can bring it back down to the mid point
            return Math.max(cachedBufferStored - bufferDelta, midPoint);
        }

        return midPoint;
    }
}
