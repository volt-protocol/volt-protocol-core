// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Constants} from "../Constants.sol";
import {PCVDeposit} from "./../pcv/PCVDeposit.sol";
import {IPCVDeposit} from "./../pcv/IPCVDeposit.sol";
import {IPegStabilityModule} from "./IPegStabilityModule.sol";
import {BasePegStabilityModule} from "./BasePegStabilityModule.sol";

contract PegStabilityModule is BasePegStabilityModule {
    using SafeERC20 for IERC20;
    using SafeCast for *;

    /// @notice construct the PSM
    /// @param coreAddress reference to core
    /// @param oracleAddress reference to oracle
    /// @param backupOracle reference to backup oracle
    /// @param decimalsNormalizer decimal normalizer for oracle price
    /// @param doInvert invert oracle price
    /// @param underlyingTokenAddress this psm uses
    /// @param floorPrice minimum acceptable oracle price
    /// @param ceilingPrice maximum  acceptable oracle price
    constructor(
        address coreAddress,
        address oracleAddress,
        address backupOracle,
        int256 decimalsNormalizer,
        bool doInvert,
        IERC20 underlyingTokenAddress,
        uint128 floorPrice,
        uint128 ceilingPrice
    )
        BasePegStabilityModule(
            coreAddress,
            oracleAddress,
            backupOracle,
            decimalsNormalizer,
            doInvert,
            underlyingTokenAddress,
            floorPrice,
            ceilingPrice
        )
    {}

    // ----------- PCV Controller Only State Changing API -----------

    /// @notice withdraw assets from PSM to an external address
    /// @param to recipient
    /// @param amount of tokens to withdraw
    function withdraw(
        address to,
        uint256 amount
    ) external onlyPCVController globalLock(2) {
        underlyingToken.safeTransfer(to, amount);
        emit Withdrawal(msg.sender, to, amount);
    }

    /// @notice withdraw ERC20 from the contract
    /// @param token address of the ERC20 to send
    /// @param to address destination of the ERC20
    /// @param amount quantity of ERC20 to send
    function withdrawERC20(
        address token,
        address to,
        uint256 amount
    ) external onlyPCVController {
        IERC20(token).safeTransfer(to, amount);
        emit WithdrawERC20(msg.sender, token, to, amount);
    }

    // ----------- Public State Changing API -----------

    /// @notice function to redeem VOLT for an underlying asset
    /// @dev does not require non-reentrant modifier because this contract
    /// stores no state. Even if USDC, DAI or any other token this contract uses
    /// had an after transfer hook, calling mint or redeem in a reentrant fashion
    /// would not allow any theft of funds, it would simply build up a call stack
    /// of orders that would need to be executed.
    /// @param to recipient of underlying tokens
    /// @param amountVoltIn amount of volt to sell
    /// @param minAmountOut of underlying tokens sent to recipient
    function redeem(
        address to,
        uint256 amountVoltIn,
        uint256 minAmountOut
    ) external override globalLock(1) returns (uint256 amountOut) {
        /// ------- Checks -------
        /// 1. current price from oracle is correct
        /// 2. how much underlying token to receive
        /// 3. underlying token to receive meets min amount out

        amountOut = getRedeemAmountOut(amountVoltIn);
        require(
            amountOut >= minAmountOut,
            "PegStabilityModule: Redeem not enough out"
        );

        /// ------- Effects / Interactions with Internal Contracts -------

        /// Do effect after interaction because you don't want to give tokens before
        /// taking the corresponding amount of Volt from the account.
        /// Replenishing buffer allows more Volt to be minted.
        volt().burnFrom(msg.sender, amountVoltIn); /// Check and Interaction with a trusted contract
        globalRateLimitedMinter().replenishBuffer(amountVoltIn); /// Effect -- interaction with a trusted contract

        /// ------- Interaction with External Contract -------

        underlyingToken.safeTransfer(to, amountOut); /// Interaction -- untrusted contract

        emit Redeem(to, amountVoltIn, amountOut);
    }

    /// @notice function to buy VOLT for an underlying asset
    /// This contract has no minting functionality, so the max
    /// amount of Volt that can be purchased is the Volt balance in the contract
    /// @dev does not require non-reentrant modifier because this contract
    /// stores no state. Even if USDC, DAI or any other token this contract uses
    /// had an after transfer hook, calling mint or redeem in a reentrant fashion
    /// would not allow any theft of funds, it would simply build up a call stack
    /// of orders that would need to be executed.
    /// @param to recipient of the Volt
    /// @param amountIn amount of underlying tokens used to purchase Volt
    /// @param minAmountVoltOut minimum amount of Volt recipient to receive
    function mint(
        address to,
        uint256 amountIn,
        uint256 minAmountVoltOut
    ) external override globalLock(1) returns (uint256 amountVoltOut) {
        /// ------- Checks -------
        /// 1. current price from oracle is correct
        /// 2. how much volt to receive
        /// 3. volt to receive meets min amount out

        amountVoltOut = getMintAmountOut(amountIn);
        require(
            amountVoltOut >= minAmountVoltOut,
            "PegStabilityModule: Mint not enough out"
        );

        /// ------- Check / Effect / Trusted Interaction -------

        /// Checks that there is enough Volt left to mint globally.
        /// This is a check as well, because if there isn't sufficient Volt to mint,
        /// then, the call to mintVolt will fail in the RateLimitedV2 class.
        globalRateLimitedMinter().mintVolt(to, amountVoltOut); /// Check, Effect, then Interaction with trusted contract

        /// ------- Interactions with Untrusted Contract -------

        underlyingToken.safeTransferFrom(msg.sender, address(this), amountIn); /// Interaction -- untrusted contract

        emit Mint(to, amountIn, amountVoltOut);
    }

    /// ----------- Public View-Only API ----------

    /// @notice returns the maximum amount of Volt that can be minted
    function getMaxMintAmountOut() external view returns (uint256) {
        return globalRateLimitedMinter().buffer();
    }
}
