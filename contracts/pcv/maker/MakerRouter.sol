// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMakerRouter} from "./IMakerRouter.sol";
import {IDSSPSM} from "./IDSSPSM.sol";
import {IPegStabilityModule} from "../../peg/IPegStabilityModule.sol";
import {CoreRef} from "../../refs/CoreRef.sol";
import {TribeRoles} from "../../core/TribeRoles.sol";
import {Constants} from "../../Constants.sol";

/// @notice This contracts allows for swaps between FEI-DAI and FEI-USDC
/// by using the FEI FEI-DAI PSM and the Maker DAI-USDC PSM
/// @author k-xo
contract MakerRouter is IMakerRouter, CoreRef {
    using SafeERC20 for IERC20;

    /// @notice reference to the Maker DAI-USDC PSM that this router interacts with
    /// @dev points to Makers DssPsm contract
    IDSSPSM public immutable daiPSM;

    /// @notice reference to the FEI FEI-DAI PSM that this router interacts with
    IPegStabilityModule public immutable feiPSM;

    /// @notice reference to the DAI contract used.
    /// @dev Router can be redeployed if DAI address changes
    IERC20 public constant DAI =
        IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    /// @notice reference to the FEI contract used.
    /// @dev Router can be redeployed if FEI address changes
    IERC20 public constant FEI =
        IERC20(0x956F47F50A910163D8BF957Cf5846D573E7f87CA);

    /// @notice scaling factor for USDC
    uint256 public constant USDC_SCALING_FACTOR = 1e12;

    constructor(
        address _core,
        IDSSPSM _daiPSM,
        IPegStabilityModule _feiPSM
    ) CoreRef(_core) {
        daiPSM = _daiPSM;
        feiPSM = _feiPSM;

        FEI.approve(address(feiPSM), type(uint256).max);
        DAI.approve(address(daiPSM), type(uint256).max);
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
    function swapAllFeiForDai(
        address to
    )
        external
        hasAnyOfTwoRoles(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER)
    {
        _redeemAllBalanceFromFeiPSM(to);
    }

    /// @notice Function to swap from FEI to USDC
    /// @dev Function will swap from FEI to DAI first then DAI to USDC
    /// @param amountFeiIn the amount of FEI to be deposited
    /// @param minDaiAmountOut the minimum amount of DAI expected to be received from FEI PSM
    /// @param to the address the USDC should be sent to once swapped
    function swapFeiForUsdc(
        uint256 amountFeiIn,
        uint256 minDaiAmountOut,
        address to
    )
        external
        hasAnyOfTwoRoles(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER)
    {
        _redeemFromFeiPSM(amountFeiIn, minDaiAmountOut, address(this));
        daiPSM.buyGem(to, (minDaiAmountOut) / USDC_SCALING_FACTOR);
    }

    /// @notice Function to swap all of FEI balance to USDC
    /// @param to the address the USDC should be sent to once swapped
    function swapAllFeiForUsdc(
        address to
    )
        external
        hasAnyOfTwoRoles(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER)
    {
        uint256 minDaiAmountOut = _redeemAllBalanceFromFeiPSM(address(this));
        daiPSM.buyGem(to, (minDaiAmountOut) / USDC_SCALING_FACTOR);
    }

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
    )
        external
        hasAnyOfTwoRoles(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER)
    {
        require(
            ratioUSDC < Constants.BASIS_POINTS_GRANULARITY && ratioUSDC > 0,
            "MakerRouter: Invalid USDC Ratio"
        );

        _redeemFromFeiPSM(amountFeiIn, minDaiAmountOut, address(this));
        _swapForUsdcAndDai(minDaiAmountOut, usdcTo, daiTo, ratioUSDC);
    }

    /// @notice Function to swap all FEI balance for both DAI and USDC
    /// @param usdcTo the address the USDC should be sent to once swapped
    /// @param daiTo the address the DAI  should be sent to once swapped
    /// @param ratioUSDC the ratio of the DAI received we would like to swap to USDC - in basis point terms
    function swapAllFeiForUsdcAndDai(
        address usdcTo,
        address daiTo,
        uint256 ratioUSDC
    )
        external
        hasAnyOfTwoRoles(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER)
    {
        uint256 minDaiAmountOut = _redeemAllBalanceFromFeiPSM(address(this));
        _swapForUsdcAndDai(minDaiAmountOut, usdcTo, daiTo, ratioUSDC);
    }

    /// @notice Function to withdraw tokens to an address
    /// @param token the token to withdraw
    /// @param amount the amount to send
    /// @param to the address the token should be sent to
    function withdrawERC20(
        address token,
        uint256 amount,
        address to
    )
        external
        hasAnyOfTwoRoles(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER)
    {
        IERC20(token).safeTransfer(to, amount);
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
        require(amountFeiIn > 1e18, "MakerRouter: Must deposit at least 1 FEI");
        FEI.safeTransferFrom(msg.sender, address(this), amountFeiIn);
        feiPSM.redeem(to, amountFeiIn, minDaiAmountOut);
    }

    /// @notice Helper function to redeem DAI max allowance or balance from the FEI FEI-DAI PSM
    /// @param to the address the DAI should be sent to once swapped
    function _redeemAllBalanceFromFeiPSM(
        address to
    ) private returns (uint256 minDaiAmountOut) {
        uint256 allowance = FEI.allowance(msg.sender, address(this));
        uint256 amountFeiIn = Math.min(FEI.balanceOf(msg.sender), allowance);

        require(amountFeiIn > 1e18, "MakerRouter: Must deposit at least 1 FEI");

        FEI.safeTransferFrom(msg.sender, address(this), amountFeiIn);
        uint256 userBalanceBefore = DAI.balanceOf(to);

        // 3 is used as there is a 3 basis points redemption fee
        minDaiAmountOut =
            (amountFeiIn * (Constants.BASIS_POINTS_GRANULARITY - 3)) /
            Constants.BASIS_POINTS_GRANULARITY;

        feiPSM.redeem(to, amountFeiIn, minDaiAmountOut);

        uint256 userBalanceAfter = DAI.balanceOf(to);

        require(
            userBalanceAfter - userBalanceBefore >= minDaiAmountOut,
            "MakerRouter: Not enough DAI received"
        );
    }

    /// @notice Helper function to swap for both DAI and USDC
    /// @param minDaiAmountOut the minimum amount of DAI expected to be received
    /// @param usdcTo the address the USDC should be sent to once swapped
    /// @param daiTo the address the DAI should be sent to once swapped
    /// @param ratioUSDC the ratio of the DAI received we would like to swap to USDC - in basis point terms
    function _swapForUsdcAndDai(
        uint256 minDaiAmountOut,
        address usdcTo,
        address daiTo,
        uint256 ratioUSDC
    ) private {
        uint256 usdcAmount = (minDaiAmountOut * ratioUSDC) /
            Constants.BASIS_POINTS_GRANULARITY;

        require(
            usdcAmount / USDC_SCALING_FACTOR != 0,
            "MakerRouter: Not enough USDC out"
        );

        daiPSM.buyGem(usdcTo, usdcAmount / USDC_SCALING_FACTOR);
        DAI.safeTransfer(daiTo, minDaiAmountOut - usdcAmount);
    }
}
