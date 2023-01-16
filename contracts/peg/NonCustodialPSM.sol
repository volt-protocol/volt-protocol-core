// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Constants} from "../Constants.sol";
import {OracleRefV2} from "./../refs/OracleRefV2.sol";
import {IPCVDeposit} from "./../pcv/IPCVDeposit.sol";
import {INonCustodialPSM} from "./INonCustodialPSM.sol";
import {BasePegStabilityModule} from "./BasePegStabilityModule.sol";

/// @notice this contract needs the PCV controller role to be able to pull funds
/// from the PCV deposit smart contract.
/// @dev This contract requires the RATE_LIMIT_SYSTEM_ENTRY_REPLENISH_ROLE
/// in order to replenish the buffer in the GlobalRateLimitedMinter.
/// @dev This contract requires the RATE_LIMIT_SYSTEM_EXIT_DEPLETE_ROLE
/// in order to deplete the buffer in the GlobalSystemExitRateLimiter.
/// This PSM is not a PCV deposit because it never holds funds, it only has permissions
/// to pull funds from a pcv deposit and replenish a global buffer.
contract NonCustodialPSM is BasePegStabilityModule, INonCustodialPSM {
    using SafeERC20 for IERC20;
    using SafeCast for *;

    /// @notice reference to the fully liquid venue redemptions can occur in
    IPCVDeposit public pcvDeposit;

    /// @notice construct the PSM
    /// @param coreAddress reference to core
    /// @param oracleAddress reference to oracle
    /// @param backupOracleAddress reference to backup oracle
    /// @param decimalNormalizer decimal normalizer for oracle price
    /// @param invert invert oracle price
    /// @param underlyingTokenAddress this psm uses
    /// @param floorPrice minimum acceptable oracle price
    /// @param ceilingPrice maximum acceptable oracle price
    constructor(
        address coreAddress,
        address oracleAddress,
        address backupOracleAddress,
        int256 decimalNormalizer,
        bool invert,
        IERC20 underlyingTokenAddress,
        uint128 floorPrice,
        uint128 ceilingPrice,
        IPCVDeposit pcvDepositAddress
    )
        BasePegStabilityModule(
            coreAddress,
            oracleAddress,
            backupOracleAddress,
            decimalNormalizer,
            invert,
            underlyingTokenAddress,
            floorPrice,
            ceilingPrice
        )
    {
        _setPCVDeposit(pcvDepositAddress);
    }

    // ----------- Governor Only State Changing API -----------

    /// @notice set the target for sending all PCV
    /// @param newTarget new PCV Deposit target for this PSM
    /// enforces that underlying on this PSM and new Deposit are the same
    function setPCVDeposit(
        IPCVDeposit newTarget
    ) external override onlyGovernor {
        _setPCVDeposit(newTarget);
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

        /// ------- Check / Effects / Trusted Interactions -------

        /// Do effect after interaction because you don't want to give tokens before
        /// taking the corresponding amount of Volt from the account.
        /// Replenishing buffer allows more Volt to be minted.
        /// None of these three external calls make calls external to the Volt System.
        volt().burnFrom(msg.sender, amountVoltIn); /// Check and Effect -- trusted contract
        globalRateLimitedMinter().replenishBuffer(amountVoltIn); /// Effect -- trusted contract
        globalSystemExitRateLimiter().depleteBuffer(getExitValue(amountOut)); /// Check and Effect -- trusted contract, reverts if buffer exhausted

        /// Interaction -- pcv deposit is trusted,
        /// however this interacts with external untrusted contracts to withdraw funds from a venue
        /// and then transfer an untrusted token to the recipient
        pcvDeposit.withdraw(to, amountOut);

        /// No PCV Oracle hooks needed here as PCV deposit will update PCV Oracle

        emit Redeem(to, amountVoltIn, amountOut);
    }

    /// @notice overriden and reverts to keep compatability with standard PSM interface
    function mint(address, uint256, uint256) external pure returns (uint256) {
        revert("NonCustodialPSM: cannot mint");
    }

    /// ----------- Public View-Only API ----------

    /// @notice overriden and reverts to keep compatability with standard PSM interface
    function getMintAmountOut(uint256) public view override returns (uint256) {
        floor; /// shhh
        revert("NonCustodialPSM: cannot mint");
    }

    /// @notice returns inverse of normal value.
    /// Used to normalize decimals to properly deplete
    /// the buffer in Global System Exit Rate Limiter
    /// @param amount to normalize
    /// @return normalized amount
    function getExitValue(uint256 amount) public view returns (uint256) {
        uint256 scalingFactor;

        if (decimalsNormalizer == 0) {
            return amount;
        }
        if (decimalsNormalizer < 0) {
            scalingFactor = 10 ** uint256(-decimalsNormalizer);
            return amount * scalingFactor;
        } else {
            scalingFactor = 10 ** uint256(decimalsNormalizer);
            return amount / scalingFactor;
        }
    }

    /// ----------- Private Helper Function -----------

    /// @notice helper function to set the PCV deposit
    /// @param newPCVDeposit the new PCV deposit that this PSM will pull assets from and deposit assets into
    function _setPCVDeposit(IPCVDeposit newPCVDeposit) private {
        require(
            newPCVDeposit.balanceReportedIn() == address(underlyingToken),
            "PegStabilityModule: Underlying token mismatch"
        );
        IPCVDeposit oldTarget = pcvDeposit;
        pcvDeposit = newPCVDeposit;

        emit PCVDepositUpdate(oldTarget, newPCVDeposit);
    }
}
