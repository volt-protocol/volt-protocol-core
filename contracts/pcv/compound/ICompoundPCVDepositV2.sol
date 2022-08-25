// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {CToken} from "./CToken.sol";
import {CErc20} from "./CErc20.sol";
import {CoreRef} from "../../refs/CoreRef.sol";
import {TribeRoles} from "../../core/TribeRoles.sol";
import {PCVDepositV2} from "../PCVDepositV2.sol";

/// @title Compound PCV Deposit
/// @author Elliot Friedman
interface ICompoundPCVDepositV2 {
    /// @notice the token underlying the cToken
    function token() external view returns (IERC20);

    /// @notice reference to the CToken this contract holds
    function cToken() external view returns (CToken);

    /// @notice scalar value used in Compound
    function EXCHANGE_RATE_SCALE() external view returns (uint256);

    /// @notice permisionless function to claim all accrued comp for this
    /// smart contract. Withdraw happens through withdraw ERC20.
    /// Gas golfed to only claim rewards for the market this contract is in
    function claimComp() external;

    /// @notice withdraw all tokens from the PCV allocation
    /// @param to the address to send proceeds
    function withdrawAll(address to) external;

    /// @notice withdraw all available tokens from the PCV allocation
    /// @param to the address to send proceeds
    function withdrawAllAvailable(address to) external;
}
