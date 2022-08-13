// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

interface IMakerRouter {
    /// @notice Function to swap from FEI to DAI
    /// @param amountFeiIn the amount of FEI to be deposited
    /// @param minDaiAmountOut the minimum amount of DAI expected to be received
    /// @param to the address the DAI should be sent to once swapped
    function swapFeiForDai(
        uint256 amountFeiIn,
        uint256 minDaiAmountOut,
        address to
    ) external;

    /// @notice Function to swap all of FEI balance to DAI
    /// @param to the address the DAI should be sent to once swapped
    function swapAllFeiForDai(address to) external;

    /// @notice Function to swap from FEI to USDC
    /// @dev Function will swap from FEI to DAI first then DAI to USDC
    /// @param amountFeiIn the amount of FEI to be deposited
    /// @param minDaiAmountOut the minimum amount of DAI expected to be received
    /// @param to the address the DAI should be sent to once swapped
    function swapFeiForUsdc(
        uint256 amountFeiIn,
        uint256 minDaiAmountOut,
        address to
    ) external;

    /// @notice Function to swap all of FEI balance to USDC
    /// @param to the address the USDC should be sent to once swapped
    function swapAllFeiForUsdc(address to) external;

    /// @notice Function to swap for both DAI and USDC
    /// @dev Function will swap from FEI to DAI first then DAI to USDC
    /// @param amountFeiIn the amount of FEI to be deposited
    /// @param minDaiAmountOut the minimum amount of DAI expected to be received
    /// @param ratioUSDC the ratio of the DAI received we would like to swap to USDC - in basis point terms
    /// @param usdcTo the address the USDC should be sent to once swapped
    /// @param daiTo the address the DAI should be sent to once swapped
    function swapFeiForUsdcAndDai(
        uint256 amountFeiIn,
        uint256 minDaiAmountOut,
        address usdcTo,
        address daiTo,
        uint256 ratioUSDC
    ) external;

    /// @notice Function to swap all FEI balance for both DAI and USDC
    /// @param usdcTo the address the USDC should be sent to once swapped
    /// @param daiTo the address the DAI  should be sent to once swapped
    /// @param ratioUSDC the ratio of the DAI received we would like to swap to USDC - in basis point terms
    function swapAllFeiForUsdcAndDai(
        address usdcTo,
        address daiTo,
        uint256 ratioUSDC
    ) external;
}
