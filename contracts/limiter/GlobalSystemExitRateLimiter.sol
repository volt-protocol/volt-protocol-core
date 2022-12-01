pragma solidity =0.8.13;

import {IGlobalSystemExitRateLimiter} from "./IGlobalSystemExitRateLimiter.sol";
import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {VoltRoles} from "../core/VoltRoles.sol";
import {RateLimitedV2} from "../utils/RateLimitedV2.sol";

/// @notice contract to control the flow of funds through the system with a rate limit.
/// In a bank run due to losses exceeding the surplus buffer, this will allow the system
/// to apply a uniform haircut to all users after the buffer is depleted.
/// All minting should flow through this smart contract.
/// Non Custodial Peg Stability Modules will be granted the VOLT_RATE_LIMITED_DEPLETER_ROLE
/// to deplete the buffer through this contract on a global rate limit.
/// ERC20Allocator will be granted both the VOLT_RATE_LIMITED_DEPLETER_ROLE and VOLT_RATE_LIMITED_REPLENISH_ROLE
/// to be able to replenish and deplete the buffer.
contract GlobalSystemExitRateLimiter is
    IGlobalSystemExitRateLimiter,
    RateLimitedV2
{
    /// @param _core reference to the core smart contract
    /// @param _maxRateLimitPerSecond maximum rate limit per second that governance can set
    /// @param _rateLimitPerSecond starting rate limit per second for Volt minting
    /// @param _bufferCap cap on buffer size for this rate limited instance
    constructor(
        address _core,
        uint256 _maxRateLimitPerSecond,
        uint128 _rateLimitPerSecond,
        uint128 _bufferCap
    )
        CoreRefV2(_core)
        RateLimitedV2(_maxRateLimitPerSecond, _rateLimitPerSecond, _bufferCap)
    {}

    /// @notice anytime PCV is pulled from a PCV deposit where it can be redeemed,
    /// or it is being redeemed, call in and deplete this buffer
    /// Pausable and depletes the global buffer
    /// @param amount the amount of dollars to deplete the buffer by
    function depleteBuffer(
        uint256 amount
    )
        external
        /// checks
        onlyVoltRole(VoltRoles.VOLT_RATE_LIMITED_DEPLETER_ROLE)
        /// system must be level 1 locked before this function can execute
        /// asserts system is inside higher level operation when this function is called
        globalLock(2)
    {
        _depleteBuffer(amount); /// check and effects
    }

    /// @notice replenish buffer by amount of dollars sent to a PCV deposit
    /// @param amount of dollars to replenish buffer by
    function replenishBuffer(
        uint256 amount
    )
        external
        /// checks
        onlyVoltRole(VoltRoles.VOLT_RATE_LIMITED_REPLENISH_ROLE)
        /// system must be level 1 locked before this function can execute
        /// asserts system is inside higher level operation when this function is called
        globalLock(2)
    {
        _replenishBuffer(amount); /// effects
    }
}
