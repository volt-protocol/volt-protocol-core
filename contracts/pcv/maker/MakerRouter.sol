// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IMakerRouter} from "./IMakerRouter.sol";
import {IDSSPSM} from "./IDSSPSM.sol";
import {IPegStabilityModule} from "../../peg/IPegStabilityModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CoreRef} from "../../refs/CoreRef.sol";
import {TribeRoles} from "../../core/TribeRoles.sol";

contract MakerRouter is IMakerRouter, CoreRef {
    using SafeERC20 for IERC20;

    IDSSPSM public immutable daiPSM;
    IPegStabilityModule public immutable feiPSM;

    IERC20 public immutable dai;
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

    function swapFeiForUsdcAndDai(
        uint256 amountFeiIn,
        uint256 minDaiAmountOut,
        uint256 ratioUSDC, // in basis point terms,
        address to
    )
        external
        hasAnyOfTwoRoles(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER)
    {
        require(ratioUSDC < 10000, "MakerRouter: USDC Ratio too high");
        fei.safeTransferFrom(msg.sender, address(this), amountFeiIn);
        feiPSM.redeem(address(this), amountFeiIn, minDaiAmountOut);

        uint256 usdcAmount = (minDaiAmountOut * ratioUSDC) / 10000;

        daiPSM.buyGem(to, usdcAmount / 1e12);
        dai.safeTransfer(to, minDaiAmountOut - usdcAmount);
    }

    function _redeemFromFeiPSM(
        uint256 amountFeiIn,
        uint256 minDaiAmountOut,
        address to
    ) private {
        fei.safeTransferFrom(msg.sender, address(this), amountFeiIn);
        feiPSM.redeem(to, amountFeiIn, minDaiAmountOut);
    }
}
