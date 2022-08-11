// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IMakerRouter} from "./IMakerRouter.sol";
import {IDSSPSM} from "./IDSSPSM.sol";
import {IPegStabilityModule} from "../../peg/IPegStabilityModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CoreRef} from "../../refs/CoreRef.sol";
import {TribeRoles} from "../../core/TribeRoles.sol";
import "hardhat/console.sol";

/// @notice This contracts allows for swaps between FEI-DAI and FEI-USDC
/// by using the FEI FEI-DAI PSM and the Maker DAI-USDC PSM
/// @author k-xo
contract MakerRouter is IMakerRouter, CoreRef {
    using SafeERC20 for IERC20;

    /// @notice reference to the Maker DAI-USDC PSM that this router interacts with
    IDSSPSM public immutable daiPSM;

    /// @notice reference to the FEI FEI-DAI PSM that this router interacts with
    IPegStabilityModule public immutable feiPSM;

    /// @notice reference to the DAI contract used.
    /// Router can be redeployed if DAI address changes
    IERC20 public immutable dai;

    /// @notice reference to the FEI contract used.
    /// Router can be redeployed if FEI address changes
    IERC20 public immutable fei;

    constructor(
        address _core,
        IDSSPSM _daiPSM,
        IPegStabilityModule _feiPSM,
        IERC20 _dai,
        IERC20 _fei
    ) CoreRef(_core) {
        daiPSM = _daiPSM;
        feiPSM = _feiPSM;

        dai = _dai;
        fei = _fei;

        fei.approve(address(feiPSM), type(uint256).max);
        dai.approve(address(daiPSM), type(uint256).max);
    }

    /// @notice Function to swap from FEI to DAI
    /// @param amountFeiIn the amount of FEI to be deposited
    /// @param minDaiAmountOut the minimum amount of DAI expected to be received
    /// @param to the address the DAI should be sent to once swapped
    function swapFeiForDai(
        uint256 amountFeiIn,
        uint256 minDaiAmountOut,
        address to
    )
        external
        hasAnyOfTwoRoles(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER)
    {
        _redeemFromFeiPSM(amountFeiIn, minDaiAmountOut, to);
    }

    /// @notice Function to swap all of FEI balance to DAI
    /// @param to the address the DAI should be sent to once swapped
    function swapAllFeiForDai(address to)
        external
        hasAnyOfTwoRoles(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER)
    {
        _redeemAllBalanceFromFeiPSM(to);
    }

    /// @notice Function to swap from FEI to DAI
    /// @dev Function will swap from FEI to DAI first then DAI to USDC
    /// @param amountFeiIn the amount of FEI to be deposited
    /// @param minDaiAmountOut the minimum amount of DAI expected to be received
    /// @param to the address the DAI should be sent to once swapped
    function swapFeiForUsdc(
        uint256 amountFeiIn,
        uint256 minDaiAmountOut,
        address to
    )
        external
        hasAnyOfTwoRoles(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER)
    {
        _redeemFromFeiPSM(amountFeiIn, minDaiAmountOut, address(this));
        daiPSM.buyGem(to, (minDaiAmountOut) / 1e12);
    }

    /// @notice Function to swap all of FEI balance to USDC
    /// @param to the address the USDC should be sent to once swapped
    function swapAllFeiForUsdc(address to)
        external
        hasAnyOfTwoRoles(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER)
    {
        uint256 minDaiAmountOut = _redeemAllBalanceFromFeiPSM(address(this));
        daiPSM.buyGem(to, (minDaiAmountOut) / 1e12);
    }

    /// @notice Function to swap for both DAI and USDC
    /// @dev Function will swap from FEI to DAI first then DAI to USDC
    /// @param amountFeiIn the amount of FEI to be deposited
    /// @param minDaiAmountOut the minimum amount of DAI expected to be received
    /// @param ratioUSDC the ratio of the DAI received we would like to swap to USDC - in basis point terms
    /// @param to the address the DAI should be sent to once swapped
    function swapFeiForUsdcAndDai(
        uint256 amountFeiIn,
        uint256 minDaiAmountOut,
        uint256 ratioUSDC,
        address to
    )
        external
        hasAnyOfTwoRoles(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER)
    {
        require(ratioUSDC < 10000, "MakerRouter: USDC Ratio too high");

        _redeemFromFeiPSM(amountFeiIn, minDaiAmountOut, address(this));
        uint256 usdcAmount = (minDaiAmountOut * ratioUSDC) / 10000;

        daiPSM.buyGem(to, usdcAmount / 1e12);
        dai.safeTransfer(to, minDaiAmountOut - usdcAmount);
    }

    /// @notice Function to swap all FEI balance for both DAI and USDC
    /// @param to the address the USDC should be sent to once swapped
    /// @param ratioUSDC the ratio of the DAI received we would like to swap to USDC - in basis point terms
    function swapAllFeiForUsdcAndDai(address to, uint256 ratioUSDC)
        external
        hasAnyOfTwoRoles(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER)
    {
        uint256 minDaiAmountOut = _redeemAllBalanceFromFeiPSM(address(this));
        uint256 usdcAmount = (minDaiAmountOut * ratioUSDC) / 10000;

        console.log(dai.balanceOf(address(this)));

        daiPSM.buyGem(to, usdcAmount / 1e12);
        dai.safeTransfer(to, minDaiAmountOut - usdcAmount);
    }

    /// @notice Helper function to redeem DAI from the FEI FEI-DAI PSM
    /// @param amountFeiIn the amount of FEI to be deposited
    /// @param minDaiAmountOut the minimum amount of DAI expected to be received
    /// @param to the address the DAI should be sent to once swapped
    function _redeemFromFeiPSM(
        uint256 amountFeiIn,
        uint256 minDaiAmountOut,
        address to
    ) private {
        fei.safeTransferFrom(msg.sender, address(this), amountFeiIn);
        feiPSM.redeem(to, amountFeiIn, minDaiAmountOut);
    }

    function _redeemAllBalanceFromFeiPSM(address to)
        private
        returns (uint256 minDaiAmountOut)
    {
        uint256 amountFeiIn = fei.balanceOf(msg.sender);
        fei.safeTransferFrom(msg.sender, address(this), amountFeiIn);

        uint256 userBalanceBefore = dai.balanceOf(to);

        minDaiAmountOut = amountFeiIn - (amountFeiIn * 3) / 10000; // 3 basis point redemption fee
        feiPSM.redeem(to, amountFeiIn, minDaiAmountOut);

        uint256 userBalanceAfter = dai.balanceOf(to);

        require(
            userBalanceAfter - userBalanceBefore >= minDaiAmountOut,
            "MakerRouter: Not enough DAI received"
        );
    }
}
