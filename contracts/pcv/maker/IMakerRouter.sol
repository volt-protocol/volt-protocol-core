// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

interface IMakerRouter {
    function swapFeiForDai(uint256 amountFeiIn, uint256 minDaiAmountOut)
        external;

    function swapFeiForUsdc(uint256 amountFeiIn, uint256 minDaiAmountOut)
        external;

    function swapFeiForUsdcAndDai(
        uint256 amountFeiIn,
        uint256 minDaiAmountOut,
        uint256 ratioUSDC
    ) external;
}
