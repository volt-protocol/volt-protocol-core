// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ILens} from "./ILens.sol";
import {IMorpho} from "./IMorpho.sol";
import {CoreRef} from "../../refs/CoreRef.sol";
import {PCVDeposit} from "../PCVDeposit.sol";
import {ICompoundOracle, ICToken} from "./ICompound.sol";

import "hardhat/console.sol";

/// @notice PCV Deposit for Morpho-Compound V2.
/// Implements the PCV Deposit interface to deposit and withdraw funds in Morpho
/// Liquidity profile of Morpho for this deposit is fully liquid for USDC and DAI
/// because the incentivized rates are higher than the P2P rate.
/// Only for depositing USDC and DAI. USDT is not in scope.
/// @dev approves the Morpho Deposit to spend this PCV deposit's token,
/// and then calls supply on Morpho, which pulls the underlying token to Morpho,
/// drawing down on the approved amount to be spent,
/// and then giving this PCV Deposit credits on Morpho in exchange for the underlying
/// @dev PCV Guardian functions withdrawERC20ToSafeAddress and withdrawAllERC20ToSafeAddress
/// will not work with removing Morpho Tokens on the Morpho PCV Deposit because Morpho
/// has no concept of mTokens. This means if the contract is paused, or an issue is
/// surfaced in Morpho and liquidity is locked, Volt will need to rely on social
/// coordination with the Morpho team to recover funds.
contract MorphoCompoundPCVDeposit is PCVDeposit, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeCast for *;

    /// @notice reference to the COMP governance token
    /// used for recording COMP rewards type in Harvest event
    address public constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;

    /// @notice reference to the lens contract for morpho-compound v2
    address public immutable lens;

    /// @notice reference to the morpho-compound v2 market
    IMorpho public immutable morpho;

    /// @notice reference to underlying token
    address public immutable token;

    /// @notice cToken in compound this deposit tracks
    /// used to inform morpho about the desired market to supply liquidity
    address public immutable cToken;

    /// @notice track the current amount of PCV deposited in the contract
    uint256 public depositedAmount;

    /// @param _core reference to the core contract
    /// @param _cToken cToken this deposit references
    /// @param _underlying Token denomination of this deposit
    /// @param _morpho reference to the morpho-compound v2 market
    /// @param _lens reference to the morpho-compound v2 lens
    constructor(
        address _core,
        address _cToken,
        address _underlying,
        address _morpho,
        address _lens
    ) CoreRef(_core) ReentrancyGuard() {
        cToken = _cToken;
        token = _underlying;
        morpho = IMorpho(_morpho);
        lens = _lens;
    }

    /// @notice Returns the distribution of assets supplied by this contract through Morpho-Compound.
    /// @return sum of suppliedP2P and suppliedOnPool for the given CToken
    function balance() public view override returns (uint256) {
        (, , uint256 totalSupplied) = ILens(lens).getCurrentSupplyBalanceInOf(
            cToken,
            address(this)
        );

        return totalSupplied;
    }

    /// @notice returns the underlying token of this deposit
    function balanceReportedIn() external view returns (address) {
        return token;
    }

    /// @notice deposit ERC-20 tokens to Morpho-Compound
    /// non-reentrant to block malicious reentrant state changes
    /// to the depositedAmount variable
    function deposit() public whenNotPaused nonReentrant {
        /// ------ Check ------

        uint256 amount = IERC20(token).balanceOf(address(this));
        if (amount == 0) {
            /// no op to prevent revert on empty deposit
            return;
        }

        /// ------ Effects ------

        /// compute profit from interest accrued and emit an event
        _recordPNL();

        /// increment tracked deposited amount
        depositedAmount += amount;

        /// ------ Interactions ------

        IERC20(token).approve(address(morpho), amount);
        morpho.supply(
            cToken, /// cToken to supply liquidity to
            address(this), /// the address of the user you want to supply on behalf of
            amount
        );

        emit Deposit(msg.sender, amount);
    }

    /// @notice withdraw tokens from the PCV allocation
    /// @param to the address PCV will be sent to
    /// @param amount of tokens withdrawn
    function withdraw(address to, uint256 amount)
        external
        onlyPCVController
        nonReentrant
    {
        _withdraw(to, amount);
    }

    /// @notice withdraw all tokens from Morpho
    /// @param to the address PCV will be sent to
    function withdrawAll(address to) external onlyPCVController nonReentrant {
        /// compute profit from interest accrued and emit an event
        _recordPNL();

        /// withdraw deposited amount as this was updated in record pnl
        _withdraw(to, depositedAmount);
    }

    /// @notice helper function to avoid repeated code in withdraw and withdrawAll
    /// anytime this function is called it is by an external function in this smart contract
    /// with a reentrancy guard. this ensures depositedAmount never desynchronizes
    /// Morpho is assumed to be a loss-less venue. over the course of less than 5 blocks,
    /// it is possible to lose funds. However, over 5 blocks, deposits are expected to always
    /// be in profit.
    /// if losses are ever sustained, subtracting amount from depositedAmount will mean
    /// that this function always reverts, meaning emergencyAction will need to be called
    function _withdraw(address to, uint256 amount) private {
        /// ------ Effects ------

        /// compute profit from interest accrued and emit an event
        _recordPNL();

        /// update tracked deposit amount
        depositedAmount -= amount;

        /// ------ Interactions ------

        morpho.withdraw(cToken, amount);
        IERC20(token).safeTransfer(to, amount);

        emit Withdrawal(msg.sender, to, amount);
    }

    /// @notice function that records how much profit has been accrued
    /// since the last call and emits an event with all profit received
    /// updates the amount deposited to include all interest earned
    function _recordPNL() private {
        /// first accrue interest in Compound and Morpho
        morpho.updateP2PIndexes(cToken);

        /// then get the current balance from the market
        uint256 currentBalance = balance();

        /// currentBalance should always be greater than or equal to
        /// the deposited amount
        int256 profit = currentBalance.toInt256() - depositedAmount.toInt256();

        /// record new deposited amount
        depositedAmount = currentBalance;

        /// profit is in underlying token
        emit Harvest(token, profit, block.timestamp);
    }

    /// @notice claim COMP rewards for supplying to Morpho
    /// no need for reentrancy lock as no smart contract state is mutated
    /// in this function.
    function harvest() external {
        address[] memory cTokens = new address[](1);
        cTokens[0] = cToken;

        /// set swap comp to morpho flag false to claim comp rewards
        uint256 claimedAmount = morpho.claimRewards(cTokens, false);

        emit Harvest(COMP, int256(claimedAmount), block.timestamp);
    }

    /// @notice function that emits an event tracking profits and losses
    /// since the last contract interaction
    /// then writes the current amount of PCV tracked in this contract
    /// to depositedAmount
    function accrue() external nonReentrant returns (uint256) {
        _recordPNL(); /// update deposit amount and fire harvest event

        return depositedAmount; /// return updated deposit amount
    }

    // ---------- Emergency Action ----------

    /// inspired by MakerDAO Multicall:
    /// https://github.com/makerdao/multicall/blob/master/src/Multicall.sol

    /// @notice struct to pack calldata and targets for an emergency action
    struct Call {
        address target;
        bytes callData;
    }

    /// @notice due to non transferability of Morpho positions,
    /// add this ability to be able to execute arbitrary calldata
    /// against arbitrary addresses.
    /// only callable by governor
    function emergencyAction(Call[] memory calls)
        external
        onlyGovernor
        returns (bytes[] memory returnData)
    {
        returnData = new bytes[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory returned) = calls[i].target.call(
                calls[i].callData
            );
            require(success);
            returnData[i] = returned;
        }
    }
}
