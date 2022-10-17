// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

interface IMigratorRouter {
    /// @notice This lets the user redeem DAI using old VOLT
    /// @param amountVoltIn the amount of old VOLT being deposited
    /// @param minAmountOut the minimum amount of DAI the user expects to receive
    function redeemDai(uint256 amountVoltIn, uint256 minAmountOut)
        external
        returns (uint256);

    /// @notice This lets the user redeem USDC using old VOLT
    /// @param amountVoltIn the amount of old VOLT being deposited
    /// @param minAmountOut the minimum amount of USDC the user expects to receive
    function redeemUSDC(uint256 amountVoltIn, uint256 minAmountOut)
        external
        returns (uint256);
}
