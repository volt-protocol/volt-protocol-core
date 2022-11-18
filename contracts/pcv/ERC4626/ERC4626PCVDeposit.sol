// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CoreRefV2} from "../../refs/CoreRefV2.sol";
import {IPCVOracle} from "../../oracle/IPCVOracle.sol";
import {PCVDeposit} from "../PCVDeposit.sol";
import {IERC4626} from "./IERC4626.sol";

/// @notice Generic PCV Deposit for a ERC4626 "Tokenized Vault"
/// - Implements the PCV Deposit interface to deposit and withdraw funds to/from a vault
/// - Implements a specific function "withdrawMax", slightly changing from "withdrawAll"
///   function that can be seen in other PCV Deposit. The reason is that the ERC4626 Vault
///   can restrict the amount of withdrawable tokens but still report the total token held
/// - Implements withdrawableBalance() which allow to get the amount of withdrawable tokens
/// @dev The underlying token in the Deposit is named "token" but is named "asset" in the Vault.
/// @dev The ERC4626 gives back "shares" when an asset is deposited. The shares are only used
/// in the vault internal accounting. The PCV Deposit does not show any values in "shares"
/// but always in "asset" (token) as explicitly stated in the function "balanceReportedIn()"
/// It should be noted that the balance() function use the 'share' amount to compute the
/// amount of token currently in possession of the PCV Deposit (with profit & loss)
contract ERC4626PCVDeposit is PCVDeposit {
    using SafeERC20 for IERC20;
    using SafeCast for *;

    /// ------------------------------------------
    /// ----------------- Event ------------------
    /// ------------------------------------------

    /// @notice emitted when the PCV Oracle address is updated
    event PCVOracleUpdated(address oldOracle, address newOracle);

    /// ------------------------------------------
    /// ---------- Immutables/Constant -----------
    /// ------------------------------------------

    /// @notice reference to ERC4626 vault
    address public immutable vault;

    /// @notice reference to underlying token
    /// @dev private because the accessor would be a duplicate
    ///      of the function 'balanceReportedIn'
    address private immutable token;

    /// ------------------------------------------
    /// ------------- State Variables -------------
    /// ------------------------------------------

    /// @notice track the last amount of PCV recorded in the contract
    /// this is the total token deposited - total token withdrawn + total PNL
    /// this is always out of date, except when accrue() is called
    /// in the same block or transaction. This means the value is stale
    /// most of the time.
    uint256 public lastRecordedBalance;

    /// @notice reference to the PCV Oracle. Settable by governance
    /// if set, anytime PCV is updated, delta is sent in to update liquid
    /// amount of PCV held
    /// not set in the constructor
    address public pcvOracle;

    /// @param _core reference to the core contract
    /// @param _underlying Token denomination of this deposit
    /// @param _vault the reference to the ERC4626 Vault the PCVDeposit interfaces
    constructor(
        address _core,
        address _underlying,
        address _vault
    ) CoreRefV2(_core) {
        token = _underlying;
        vault = _vault;

        // check that the vault's asset is equal to the PCVDeposit token
        require(
            IERC4626(vault).asset() == token,
            "ERC4626PCVDeposit: Underlying mismatch"
        );
    }

    /// ------------------------------------------
    /// ------------------ Views -----------------
    /// ------------------------------------------

    /// @notice Return the balance in underlying
    /// @return balance balance in underlying with PnL from the vault
    function balance() public view override returns (uint256) {
        // get the amount of shares owned by the PCVDeposit
        uint256 pcvDepositShares = IERC4626(vault).balanceOf(address(this));

        // preview the redeem of all the shares to underlying token
        return IERC4626(vault).previewRedeem(pcvDepositShares);
    }

    /// @notice Returns the amount of tokens that can be withdrawn at the time of the query
    ///         should be <= balance()
    /// @return reddemableBalance amount of token that can be withdrawn at the time of the query
    function withdrawableBalance() public view returns (uint256) {
        return IERC4626(vault).maxWithdraw(address(this));
    }

    /// @notice returns the underlying token of this deposit
    function balanceReportedIn() external view returns (address) {
        return token;
    }

    /// ------------------------------------------
    /// ----------- Permissionless API -----------
    /// ------------------------------------------

    /// @notice deposit an ERC-20 tokens to the ERC4626-Vault
    /// @dev TODO ADD NON REENTRANT PROTECTION WHEN AVAILABLE
    function deposit() public whenNotPaused {
        /// ------ Check ------

        uint256 amount = IERC20(token).balanceOf(address(this));
        if (amount == 0) {
            /// no op to prevent revert on empty deposit
            return;
        }

        int256 startingRecordedBalance = lastRecordedBalance.toInt256();

        /// ------ Effects ------

        /// compute profit from interest accrued and emit an event
        /// if any profits or losses are realized
        _recordPNL();

        /// increment tracked recorded amount
        /// this will be off by a hair, after a single block
        /// negative delta turns to positive delta (assuming no loss).
        lastRecordedBalance += amount;

        /// ------ Interactions ------

        IERC20(token).approve(address(vault), amount);
        IERC4626(vault).deposit(
            amount, /// amount of token to send to the vault
            address(this) /// the address of the user you want to supply on behalf of*
        );

        int256 endingRecordedBalance = balance().toInt256();

        _updateOracle(endingRecordedBalance - startingRecordedBalance);

        emit Deposit(msg.sender, amount);
    }

    /// @notice function that emits an event tracking profits and losses
    ///         since the last contract interaction
    ///         then writes the current amount of PCV tracked in this contract
    ///         to lastRecordedBalance
    /// @dev TODO ADD NON REENTRANT PROTECTION WHEN AVAILABLE
    /// @return the amount deposited after adding accrued interest or realizing losses
    function accrue() external whenNotPaused returns (uint256) {
        int256 startingRecordedBalance = lastRecordedBalance.toInt256();

        _recordPNL(); /// update deposit amount and fire harvest event

        int256 endingRecordedBalance = lastRecordedBalance.toInt256();

        _updateOracle(endingRecordedBalance - startingRecordedBalance);

        return lastRecordedBalance; /// return updated pcv amount
    }

    /// ------------------------------------------
    /// ------------ Permissioned API ------------
    /// ------------------------------------------

    /// @notice withdraw tokens from the PCV allocation
    /// non-reentrant as state changes and external calls are made
    /// @dev TODO ADD NON REENTRANT PROTECTION WHEN AVAILABLE
    /// @param to the address PCV will be sent to
    /// @param amount of tokens withdrawn
    function withdraw(address to, uint256 amount) external onlyPCVController {
        int256 startingRecordedBalance = lastRecordedBalance.toInt256();

        /// compute profit from interest accrued and emit an event
        _recordPNL();

        _withdraw(to, amount);

        int256 endingRecordedBalance = lastRecordedBalance.toInt256();

        _updateOracle(endingRecordedBalance - startingRecordedBalance);
    }

    /// @notice withdraw all withdrawable tokens from the vault
    ///         This is slightly different than a withdrawAll function
    ///         as the vault might not let the PCVDeposit to redeem all
    ///         its shares directly. Example if a Maple Vault does not have
    ///         enough liquidity because most of it has been borrowed
    /// @dev TODO ADD NON REENTRANT PROTECTION WHEN AVAILABLE
    /// @param to the address PCV will be sent to
    function withdrawMax(address to) external onlyPCVController {
        int256 startingRecordedBalance = lastRecordedBalance.toInt256();

        /// compute profit from interest accrued and emit an event
        _recordPNL();

        /// withdraw last recorded amount as this was updated in record pnl
        _withdraw(to, withdrawableBalance());

        int256 endingRecordedBalance = lastRecordedBalance.toInt256();

        _updateOracle(endingRecordedBalance - startingRecordedBalance);
    }

    /// @notice set the pcv oracle address
    /// @param _pcvOracle new pcv oracle to reference
    function setPCVOracle(address _pcvOracle) external onlyGovernor {
        address oldOracle = pcvOracle;
        pcvOracle = _pcvOracle;

        _recordPNL();

        _updateOracle(lastRecordedBalance.toInt256());

        emit PCVOracleUpdated(oldOracle, _pcvOracle);
    }

    /// ------------------------------------------
    /// ------------- Helper Methods -------------
    /// ------------------------------------------

    /// @notice update the PCVOracle if the oracle is set and the updated value is not 0
    function _updateOracle(int256 delta) private {
        if (pcvOracle != address(0) && delta != 0) {
            IPCVOracle(pcvOracle).updateLiquidBalance(delta);
        }
    }

    /// @notice helper function to avoid repeated code in withdraw and withdrawMax
    /// anytime this function is called it is by an external function in this smart contract
    /// with a reentrancy guard. This ensures lastRecordedBalance never desynchronizes.
    /// Morpho is assumed to be a loss-less venue. over the course of less than 1 block,
    /// it is possible to lose funds. However, after 1 block, deposits are expected to always
    /// be in profit at least with current interest rates around 0.8% natively on Compound,
    /// ignoring all COMP and Morpho rewards.
    /// @param to recipient of withdraw funds
    /// @param amount to withdraw
    function _withdraw(address to, uint256 amount) private {
        /// ------ Effects ------

        /// update last recorded balance amount
        /// if more than is owned is withdrawn, this line will revert
        /// this line of code is both a check, and an effect
        lastRecordedBalance -= amount;

        /// ------ Interactions ------

        IERC4626(vault).withdraw(
            amount,
            to, // receiver
            address(this) // owner of the tokens
        );

        emit Withdrawal(msg.sender, to, amount);
    }

    /// @notice records how much profit or loss has been accrued
    /// since the last call and emits an event with all profit or loss received.
    /// Updates the lastRecordedBalance to include all realized profits or losses.
    function _recordPNL() private {
        /// ------ Check ------

        /// get the current balance from the vault
        uint256 currentBalance = balance();

        /// save gas if contract has no balance
        /// if cost basis is 0 and last recorded balance is 0
        /// there is no profit or loss to record and no reason
        /// to update lastRecordedBalance
        if (currentBalance == 0 && lastRecordedBalance == 0) {
            return;
        }

        /// currentBalance should always be greater than or equal to
        /// the deposited amount, except on the same block a deposit occurs
        /// or if we're at loss in the vault
        int256 profit = currentBalance.toInt256() -
            lastRecordedBalance.toInt256();

        /// ------ Effects ------

        /// record new deposited amount
        lastRecordedBalance = currentBalance;

        /// profit is in underlying token
        emit Harvest(token, profit, block.timestamp);
    }
}
