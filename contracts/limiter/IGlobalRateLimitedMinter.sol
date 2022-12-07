// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IRateLimitedV2} from "../utils/IRateLimitedV2.sol";

interface IGlobalRateLimitedMinter is IRateLimitedV2 {
    /// @notice function that all VOLT minters call to mint VOLT
    /// pausable and depletes the msg.sender's buffer
    /// @param to the recipient address of the minted VOLT
    /// @param amount the amount of VOLT to mint
    /// only callable by those with RATE_LIMIT_SYSTEM_ENTRY_DEPLETE_ROLE
    function mintVolt(address to, uint256 amount) external;

    /// @notice replenish buffer by amount of volt tokens burned
    function replenishBuffer(uint256 amount) external;
}
