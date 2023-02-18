// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IGlobalRateLimitedMinter} from "@voltprotocol/rate-limits/IGlobalRateLimitedMinter.sol";
import {CoreRefV2} from "@voltprotocol/refs/CoreRefV2.sol";
import {VoltRoles} from "@voltprotocol/core/VoltRoles.sol";
import {RateLimitedV2} from "@voltprotocol/utils/RateLimitedV2.sol";

/// @notice contract to mint Volt on a rate limit.
/// All minting should flow through this smart contract.
/// Peg Stability Modules will be granted the RATE_LIMIT_SYSTEM_ENTRY_DEPLETE_ROLE to mint Volt
/// through this contract on a global rate limit.
/// Peg Stability Modules will be granted the RATE_LIMIT_SYSTEM_ENTRY_REPLENISH_ROLE to replenish
/// this contract's on a global rate limit when burning Volt.
contract GlobalRateLimitedMinter is IGlobalRateLimitedMinter, RateLimitedV2 {

    /// @param _core reference to the core smart contract
    /// @param _maxRateLimitPerSecond maximum rate limit per second that governance can set
    /// @param _rateLimitPerSecond starting rate limit per second for Volt minting
    /// @param _bufferCap cap on buffer size for this rate limited instance
    constructor(
        address _core,
        uint256 _maxRateLimitPerSecond,
        uint64 _rateLimitPerSecond,
        uint96 _bufferCap
    )
        CoreRefV2(_core)
        RateLimitedV2(_maxRateLimitPerSecond, _rateLimitPerSecond, _bufferCap)
    {}

    /// @notice all VOLT minters can call to mint VOLT
    /// Pausable and depletes the global buffer
    /// @param to the recipient address of the minted VOLT
    /// @param amount the amount of VOLT to mint
    function mintVolt(
        address to,
        uint256 amount
    )
        external
        /// checks
        onlyVoltRole(VoltRoles.PSM_MINTER)
        /// system must be level 1 locked before this function can execute
        /// asserts system is inside PSM mint when this function is called
        globalLock(2)
    {
        _depleteBuffer(amount); /// check and effects
        volt().mint(to, amount); /// interactions
    }

    /// @notice replenish buffer by amount of Volt tokens burned
    /// @param amount of Volt to replenish buffer by
    function replenishBuffer(
        uint256 amount
    )
        external
        /// checks
        onlyVoltRole(VoltRoles.PSM_MINTER)
        /// system must be level 1 locked before this function can execute
        /// asserts system is inside PSM redeem when this function is called
        globalLock(2)
    {
        _replenishBuffer(amount); /// effects
    }
}

/// two goals:
/// 1. cap the Volt supply and creation of new Volt to 5.8m
/// 2. slow the redemption of Volt to only allow .5m per day to leave the system.
