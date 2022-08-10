// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

interface IMakerRouter {
    function swapFeiForDai(
        uint256 amountFeiIn,
        uint256 minDaiAmountOut,
        address to
    ) external;

    function swapFeiForUsdc(
        uint256 amountFeiIn,
        uint256 minDaiAmountOut,
        address to
    ) external;

    function swapFeiForUsdcAndDai(
        uint256 amountFeiIn,
        uint256 minDaiAmountOut,
        uint256 ratioUSDC,
        address to
    ) external;
}
