// SPDX-License-Identifier = GPL-3.0-or-later
pragma solidity 0.8.13;

library LinearInterpolation {
    /// Linear Interpolation Formula
    /// (y) = y1 + (x − x1) * ((y2 − y1) / (x2 − x1))
    /// @notice calculate linear interpolation and return ending price
    /// @param x is time value to calculate interpolation on
    /// @param x1 is starting time to calculate interpolation from
    /// @param x2 is ending time to calculate interpolation to
    /// @param y1 is starting price to calculate interpolation from
    /// @param y2 is ending price to calculate interpolation to
    function lerp(
        uint256 x,
        uint256 x1,
        uint256 x2,
        uint256 y1,
        uint256 y2
    ) internal pure returns (uint256 y) {
        uint256 firstDeltaX = x - x1; /// will not overflow because x should always be gte x1
        uint256 secondDeltaX = x2 - x1; /// will not overflow because x2 should always be gt x1
        uint256 deltaY = y2 - y1; /// will not overflow because y2 should always be gt y1
        uint256 product = (firstDeltaX * deltaY) / secondDeltaX;
        y = product + y1;
    }
}
