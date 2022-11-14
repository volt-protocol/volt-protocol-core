pragma solidity =0.8.13;

import {IGRLM} from "./IGRLM.sol";
import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {VoltRoles} from "../core/VoltRoles.sol";
import {RateLimitedV2} from "../utils/RateLimitedV2.sol";

/// @notice contract to mint Volt on a rate limit.
/// All minting should flow through this smart contract.
/// Peg Stability Modules will be granted the VOLT_RATE_LIMITED_MINTER_ROLE to mint Volt
/// through this contract on a global rate limit.
contract GlobalRateLimitedMinter is IGRLM, RateLimitedV2 {
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
        onlyVoltRole(VoltRoles.VOLT_RATE_LIMITED_MINTER_ROLE)
        isGlobalReentrancyLocked
    {
        _depleteBuffer(amount); /// check and effects
        volt().mint(to, amount); /// interactions
    }

    /// @notice replenish buffer by amount of volt tokens burned
    function replenishBuffer(
        uint256 amount
    )
        external
        /// checks
        hasAnyOfTwoRoles(
            VoltRoles.VOLT_RATE_LIMITED_MINTER_ROLE,
            VoltRoles.NON_CUSTODIAL_PSM
        )
        isGlobalReentrancyLocked
    {
        _replenishBuffer(amount); /// effects
    }
}
