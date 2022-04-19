// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {IPSMRouter} from "./IPSMRouter.sol";
import {NonCustodialPSM, INonCustodialPSM} from "./NonCustodialPSM.sol";
import {RateLimited} from "../utils/RateLimited.sol";
import {IPCVDepositBalances} from "../pcv/IPCVDepositBalances.sol";
import {IVolt} from "../volt/IVolt.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice the PSM router is an ungoverned, non custodial contract that allows user to convert their DAI to FEI
/// by interacting with the FEI/DAI PSM and then convert that FEI to VOLT, and vice versa.
contract PSMRouter is IPSMRouter {
    using SafeERC20 for IERC20;

    /// @notice reference to the PSM that this router interacts with
    INonCustodialPSM public immutable override voltPsm;

    /// @notice reference to the PSM that this router interacts with
    INonCustodialPSM public immutable override feiPsm;

    /// @notice reference to the Volt contract used.
    /// Router can be redeployed if Volt address changes
    IVolt public immutable override volt;

    /// @notice reference to the FEI contract used.
    /// Router can be redeployed if FEI address changes
    IVolt public immutable override fei;

    /// @notice reference to the DAI contract used.
    /// Router can be redeployed if DAI address changes
    IERC20 public immutable override dai;

    constructor(
        INonCustodialPSM _voltPsm,
        INonCustodialPSM _feiPsm,
        IVolt _volt,
        IVolt _fei,
        IERC20 _dai
    ) {
        voltPsm = _voltPsm;
        feiPsm = _feiPsm;
        volt = _volt;
        fei = _fei;
        dai = _dai;

        // Volt PSM approvals only interacts with VOLT/FEI
        _volt.approve(address(_voltPsm), type(uint256).max);
        _fei.approve(address(_voltPsm), type(uint256).max);

        // FEI PSM approvals only interacts with FEI/DAI
        _fei.approve(address(_feiPsm), type(uint256).max);
        _dai.approve(address(_feiPsm), type(uint256).max);
    }

    // ----------- Public View-Only API ----------

    /// @notice view only pass through function to get amount of VOLT out with given amount of DAI in
    function getMintAmountOut(uint256 amountIn)
        public
        view
        override
        returns (uint256 amountVoltOut)
    {
        uint256 amountFeiOut = feiPsm.getMintAmountOut(amountIn);
        amountVoltOut = voltPsm.getMintAmountOut(amountFeiOut);
    }

    /// @notice view only pass through function to get amount of DAI out with given amount of VOLT in
    function getRedeemAmountOut(uint256 amountVoltIn)
        public
        view
        returns (uint256 amountOut)
    {
        uint256 amountFeiOut = voltPsm.getRedeemAmountOut(amountVoltIn);
        amountOut = feiPsm.getRedeemAmountOut(amountFeiOut);
    }

    /// @notice the maximum mint amount out
    function getMaxMintAmountOut() external view override returns (uint256) {
        return voltPsm.getMaxMintAmountOut();
    }

    // ---------- Public State-Changing API ----------

    /// @notice Mints VOLT to the given address, with a minimum amount required
    /// @dev This converts DAI to FEI using the FEI PSM and then mints VOLT using the VOLT PSM
    /// @param to The address to mint VOLT to
    /// @param minVoltAmountOut The minimum amount of VOLT to mint
    function mint(
        address to,
        uint256 minVoltAmountOut,
        uint256 daiAmountIn
    ) external override returns (uint256) {
        return _mint(to, minVoltAmountOut, daiAmountIn);
    }

    /// @notice Redeems Volt for Dai
    /// First pull user Volt into this contract
    /// Then call redeem on the PSM to turn the Volt into FEI
    /// Call the FEI/DAI PSM to convert the FEI to DAI
    /// Send the DAI to the specified recipient
    /// @param to the address to receive the DAI
    /// @param amountVoltIn the amount of VOLT to redeem
    /// @param minDaiAmountOut the minimum amount of DAI to receive
    function redeem(
        address to,
        uint256 amountVoltIn,
        uint256 minDaiAmountOut
    ) external override returns (uint256) {
        return _redeem(to, amountVoltIn, minDaiAmountOut);
    }

    // ---------- Internal Methods ----------

    /// @notice helper function to wrap eth and handle mint call to PSM
    function _mint(
        address _to,
        uint256 _minVoltAmountOut,
        uint256 _daiAmountIn
    ) internal returns (uint256 amountOut) {
        dai.safeTransferFrom(msg.sender, address(this), _daiAmountIn);
        uint256 amountFeiOut = feiPsm.mint(address(this), _daiAmountIn, 0);

        amountOut = voltPsm.mint(_to, amountFeiOut, _minVoltAmountOut);
    }

    /// @notice helper function to deposit user VOLT, convert to FEI and send DAI back to the user
    /// the PSM router receives the DAI, then sends it to the specified recipient.
    function _redeem(
        address _to,
        uint256 _amountVoltIn,
        uint256 _minDaiAmountOut
    ) internal returns (uint256 amountOut) {
        IERC20(volt).safeTransferFrom(msg.sender, address(this), _amountVoltIn);
        uint256 amountFeiOut = voltPsm.redeem(address(this), _amountVoltIn, 0);

        amountOut = feiPsm.redeem(_to, amountFeiOut, _minDaiAmountOut);
    }
}
