// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {console} from "@forge-std/console.sol";

import {CoreRefV2} from "@voltprotocol/refs/CoreRefV2.sol";
import {IRateLimitedV2} from "@voltprotocol/utils/IRateLimitedV2.sol";

/// @title abstract contract for putting a rate limit on how fast a contract
/// can perform an action e.g. Minting
/// Rate limit contract has a mid point that it tries to maintain.
/// When the stored buffer is above the mid point, time depletes the buffer
/// When the stored buffer is below the mid point, time replenishes the buffer
/// When buffer stored is at the mid point, do nothing
/// This contract is designed to allow both minting and redeeming
/// Mints deplete the buffer, and redeems replenish the buffer.
/// Deplete the buffer past 0 and execution reverts
/// Replenish the buffer past the buffer cap and execution reverts
/// @author Elliot Friedman
abstract contract RateLimitedV2 is IRateLimitedV2, CoreRefV2 {
    using SafeCast for *;

    /// @notice maximum rate limit per second governance can set for this contract
    uint256 public immutable MAX_RATE_LIMIT_PER_SECOND;

    /// ------------- First Storage Slot -------------

    /// @notice the rate per second for this contract
    uint64 public rateLimitPerSecond;

    /// @notice the cap of the buffer that can be used at once
    uint96 public bufferCap;

    /// @notice buffercap / 2
    uint96 public midPoint;

    /// ------------- Second Storage Slot -------------

    /// @notice the last time the buffer was used by the contract
    uint32 public lastBufferUsedTime;

    /// @notice the buffer at the timestamp of lastBufferUsedTime
    uint224 public bufferStored;

    /// @notice RateLimitedV2 constructor
    /// @param _maxRateLimitPerSecond maximum rate limit per second that governance can set
    /// @param _rateLimitPerSecond starting rate limit per second
    /// @param _bufferCap cap on buffer size for this rate limited instance
    constructor(
        uint256 _maxRateLimitPerSecond,
        uint64 _rateLimitPerSecond,
        uint96 _bufferCap
    ) {
        lastBufferUsedTime = block.timestamp.toUint32();
        _setBufferCap(_bufferCap);
        bufferStored = _bufferCap;

        require(
            _rateLimitPerSecond <= _maxRateLimitPerSecond,
            "RateLimited: rateLimitPerSecond too high"
        );
        _setRateLimitPerSecond(_rateLimitPerSecond);

        bufferStored = _bufferCap / 2; /// cached buffer starts at midpoint
        MAX_RATE_LIMIT_PER_SECOND = _maxRateLimitPerSecond;
    }

    /// @notice set the rate limit per second
    function setRateLimitPerSecond(
        uint64 newRateLimitPerSecond
    ) external virtual onlyGovernor {
        require(
            newRateLimitPerSecond <= MAX_RATE_LIMIT_PER_SECOND,
            "RateLimited: rateLimitPerSecond too high"
        );
        _updateBufferStored();

        _setRateLimitPerSecond(newRateLimitPerSecond);
    }

    /// @notice set the buffer cap
    function setBufferCap(uint96 newBufferCap) external virtual onlyGovernor {
        _setBufferCap(newBufferCap);
    }

    /// @notice the amount of action used before hitting limit
    /// @dev replenishes at rateLimitPerSecond per second up to bufferCap
    function buffer() public view returns (uint256) {
        uint256 elapsed = block.timestamp.toUint32() - lastBufferUsedTime;
        uint256 cachedBufferStored = bufferStored;
        uint256 bufferDelta = rateLimitPerSecond * elapsed;

        console.log("midPoint: ", midPoint);
        console.log("bufferDelta: ", bufferDelta);
        console.log("bufferStored: ", cachedBufferStored);

        /// converge on mid point
        if (cachedBufferStored < midPoint) {
            /// buffer is below mid point, time accumulation can bring it back up to the mid point
            return Math.min(cachedBufferStored + bufferDelta, midPoint);
        } else if (cachedBufferStored > midPoint) {
            /// buffer is above the mid point, time accumulation can bring it back down to the mid point
            return Math.max(cachedBufferStored - bufferDelta, midPoint);
        }

        console.log("returning buffer stored");
        /// if already at mid point, do nothing
        return cachedBufferStored;
    }

    /// @notice the method that enforces the rate limit.
    /// Decreases buffer by "amount".
    /// If buffer is <= amount, revert
    function _depleteBuffer(uint256 amount) internal {
        uint256 newBuffer = buffer();

        require(newBuffer != 0, "RateLimited: no rate limit buffer");
        require(amount <= newBuffer, "RateLimited: rate limit hit");

        uint32 blockTimestamp = block.timestamp.toUint32();
        uint224 newBufferStored = (newBuffer - amount).toUint224();

        /// gas optimization to only use a single SSTORE
        lastBufferUsedTime = blockTimestamp;
        bufferStored = newBufferStored;

        emit BufferUsed(amount, newBufferStored); /// save single warm SLOAD with `newBufferStored`
    }

    /// @notice function to replenish buffer
    /// cannot increase buffer if result would be gt buffer cap
    /// @param amount to increase buffer by if under buffer cap
    function _replenishBuffer(uint256 amount) internal {
        uint256 newBuffer = buffer();

        uint256 _bufferCap = bufferCap; /// gas opti, save an SLOAD

        require(
            newBuffer + amount <= _bufferCap,
            "RateLimited: buffer cap overflow"
        );

        uint32 blockTimestamp = block.timestamp.toUint32();

        /// bufferStored cannot be gt buffer cap because of check
        /// newBuffer + amount <= buffer cap
        uint224 newBufferStored = uint224(newBuffer + amount);

        /// gas optimization to only use a single SSTORE
        lastBufferUsedTime = blockTimestamp;
        bufferStored = newBufferStored;

        emit BufferReplenished(amount, bufferStored);
    }

    function _setRateLimitPerSecond(uint64 newRateLimitPerSecond) internal {
        uint256 oldRateLimitPerSecond = rateLimitPerSecond;
        rateLimitPerSecond = newRateLimitPerSecond;

        emit RateLimitPerSecondUpdate(
            oldRateLimitPerSecond,
            newRateLimitPerSecond
        );
    }

    function _setBufferCap(uint96 newBufferCap) internal {
        _updateBufferStored();

        uint256 oldBufferCap = bufferCap;
        uint96 newMidPoint = newBufferCap / 2;
        midPoint = newMidPoint; /// start at midpoint
        bufferCap = newBufferCap; /// set buffer cap

        emit BufferCapUpdate(oldBufferCap, newBufferCap);
    }

    function _updateBufferStored() internal {
        uint224 newBufferStored = buffer().toUint224();
        uint32 newBlockTimestamp = block.timestamp.toUint32();

        bufferStored = newBufferStored;
        lastBufferUsedTime = newBlockTimestamp;
    }
}
