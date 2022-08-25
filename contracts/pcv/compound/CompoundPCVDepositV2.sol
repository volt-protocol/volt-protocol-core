// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {CToken} from "./CToken.sol";
import {CErc20} from "./CErc20.sol";
import {CoreRef} from "../../refs/CoreRef.sol";
import {TribeRoles} from "../../core/TribeRoles.sol";
import {Comptroller} from "./Comptroller.sol";
import {ICompoundPCVDepositV2} from "./ICompoundPCVDepositV2.sol";
import {PCVDepositV2} from "../PCVDepositV2.sol";

/// @title Compound PCV Deposit
/// @author Volt Protocol
contract CompoundPCVDepositV2 is ICompoundPCVDepositV2, PCVDepositV2 {
    using SafeERC20 for IERC20;

    /// @notice the token underlying the cToken
    IERC20 public immutable token;

    /// @notice reference to the CToken this contract holds
    CToken public immutable cToken;

    /// @notice reference to the comptroller smart contract
    Comptroller public immutable comptroller;

    /// @notice scalar value used in Compound
    uint256 public constant EXCHANGE_RATE_SCALE = 1e18;

    /// @notice Compound PCV Deposit constructor
    /// @param _core Fei Core for reference
    /// @param _cToken Compound cToken to deposit
    constructor(address _core, address _cToken) CoreRef(_core) {
        cToken = CToken(_cToken);
        token = IERC20(CErc20(_cToken).underlying());
        comptroller = CToken(_cToken).comptroller();
        require(cToken.isCToken(), "CompoundPCVDepositV2: Not a cToken");
    }

    /// @notice permisionless function to claim all accrued comp for this
    /// smart contract. Withdraw happens through withdraw ERC20.
    /// Gas golfed to only claim rewards for the market this contract is in
    function claimComp() external {
        CToken[] memory cTokens = new CToken[](1);
        address[] memory holder = new address[](1);

        holder[0] = address(this);
        cTokens[0] = cToken;

        /// this smart contract is supply only, so do not claim borrow rewards
        comptroller.claimComp(holder, cTokens, false, true);
    }

    /// @notice deposit ERC-20 tokens to Compound
    function deposit() external override whenNotPaused {
        uint256 amount = token.balanceOf(address(this));

        token.approve(address(cToken), amount);

        // Compound returns non-zero when there is an error
        require(
            CErc20(address(cToken)).mint(amount) == 0,
            "ERC20CompoundPCVDeposit: deposit error"
        );

        emit Deposit(msg.sender, amount);
    }

    /// @notice withdraw tokens from the PCV allocation
    /// @param amountUnderlying of tokens withdrawn
    /// @param to the address to send proceeds
    function withdraw(address to, uint256 amountUnderlying)
        external
        override
        hasAnyOfTwoRoles(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER)
        whenNotPaused
    {
        _withdraw(to, amountUnderlying);
    }

    /// @notice withdraw all tokens from the PCV allocation
    /// @param to the address to send proceeds
    function withdrawAll(address to)
        external
        hasAnyOfTwoRoles(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER)
        whenNotPaused
    {
        uint256 amountUnderlying = balance();
        _withdraw(to, amountUnderlying);
    }

    /// @notice withdraw all available tokens from the PCV allocation
    /// @param to the address to send proceeds
    function withdrawAllAvailable(address to)
        external
        hasAnyOfTwoRoles(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER)
        whenNotPaused
    {
        uint256 amountUnderlying = balance(); /// try to withdraw all POL from compound
        _withdrawAllAvailable(to, amountUnderlying);
    }

    /// @notice helper function to withdraw specified amount of compound liquidity
    function _withdraw(address to, uint256 amountUnderlying) internal {
        require(
            cToken.redeemUnderlying(amountUnderlying) == 0,
            "CompoundPCVDeposit: redeem error"
        );
        token.safeTransfer(to, amountUnderlying);

        emit Withdrawal(msg.sender, to, amountUnderlying);
    }

    /// @notice helper function to withdraw all available compound liquidity,
    /// or specified amount, whichever is smaller
    function _withdrawAllAvailable(address to, uint256 amountUnderlying)
        internal
    {
        uint256 redeemAmount = Math.min(
            token.balanceOf(address(cToken)),
            amountUnderlying
        );
        _withdraw(to, redeemAmount);
    }

    /// ---------- View Functions ----------

    /// @notice returns total balance of PCV in the Deposit excluding the FEI
    /// @dev returns stale values from Compound if the market hasn't been updated
    function balance() public view override returns (uint256) {
        uint256 exchangeRate = cToken.exchangeRateStored();
        return
            (cToken.balanceOf(address(this)) * exchangeRate) /
            EXCHANGE_RATE_SCALE;
    }

    /// @notice token that the balance is reported in
    function balanceReportedIn() public view override returns (address) {
        return address(token);
    }
}
