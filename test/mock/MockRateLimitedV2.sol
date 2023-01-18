pragma solidity =0.8.13;

import "@voltprotocol/utils/RateLimitedV2.sol";
import "@voltprotocol/refs/CoreRef.sol";

contract MockRateLimitedV2 is RateLimitedV2 {
    constructor(
        address _core,
        uint256 _maxRateLimitPerSecond,
        uint128 _rateLimitPerSecond,
        uint128 _bufferCap
    )
        RateLimitedV2(_maxRateLimitPerSecond, _rateLimitPerSecond, _bufferCap)
        CoreRefV2(_core)
    {}

    function depleteBuffer(uint256 amount) public {
        _depleteBuffer(amount);
    }

    function replenishBuffer(uint256 amount) public {
        _replenishBuffer(amount);
    }
}
