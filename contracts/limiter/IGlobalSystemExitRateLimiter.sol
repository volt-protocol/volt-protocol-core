// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IRateLimitedV2} from "../utils/IRateLimitedV2.sol";

interface IGlobalSystemExitRateLimiter is IRateLimitedV2 {
    /// @notice anytime PCV is pulled from a PCV deposit where it can be redeemed,
    /// or it is being redeemed, call in and deplete this buffer
    /// Pausable and depletes the global buffer
    /// @param amount the amount of dollars to deplete the buffer by
    function depleteBuffer(uint256 amount) external;

    /// @notice replenish buffer by amount of dollars sent to a PCV deposit
    /// @param amount of dollars to replenish buffer by
    function replenishBuffer(uint256 amount) external;
}
