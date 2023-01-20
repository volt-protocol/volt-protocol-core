// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ILens} from "@voltprotocol/pcv/morpho/ILens.sol";
import {IMorpho} from "@voltprotocol/pcv/morpho/IMorpho.sol";
import {CoreRefV2} from "@voltprotocol/refs/CoreRefV2.sol";
import {Constants} from "@voltprotocol/Constants.sol";
import {PCVDepositV2} from "@voltprotocol/pcv/PCVDepositV2.sol";

/// @notice PCV Deposit for Morpho-Aave V2.
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
/// @dev Depositing and withdrawing in a single block will cause a very small loss
/// of funds, less than a pip. The way to not realize this loss is by depositing and
/// then withdrawing at least 1 block later. That way, interest accrues.
/// This is not a Morpho specific issue.
/// TODO confirm that Aave rounds in the protocol's favor.
/// The issue is caused by constraints inherent to solidity and the EVM.
/// There are no floating point numbers, this means there is precision loss,
/// and protocol engineers are forced to choose who to round in favor of.
/// Engineers must round in favor of the protocol to avoid deposits of 0 giving
/// the user a balance.
contract MorphoAavePCVDeposit is PCVDepositV2 {
    using SafeERC20 for IERC20;

    /// ------------------------------------------
    /// ---------- Immutables/Constant -----------
    /// ------------------------------------------

    /// @notice reference to the lens contract for morpho-aave v2
    address public immutable lens;

    /// @notice reference to the morpho-aave v2 market
    address public immutable morpho;

    /// @notice aToken in aave this deposit tracks
    /// used to inform morpho about the desired market to supply liquidity
    address public immutable aToken;

    /// @param _core reference to the core contract
    /// @param _aToken aToken this deposit references
    /// @param _underlying Token denomination of this deposit
    /// @param _rewardToken Reward token denomination of this deposit
    /// @param _morpho reference to the morpho-compound v2 market
    /// @param _lens reference to the morpho-compound v2 lens
    constructor(
        address _core,
        address _aToken,
        address _underlying,
        address _rewardToken,
        address _morpho,
        address _lens
    ) PCVDepositV2(_underlying, _rewardToken) CoreRefV2(_core) {
        aToken = _aToken;
        morpho = _morpho;
        lens = _lens;
    }

    /// ------------------------------------------
    /// ------------------ Views -----------------
    /// ------------------------------------------

    /// @notice Returns the distribution of assets supplied by this contract through Morpho-Compound.
    /// @return sum of suppliedP2P and suppliedOnPool for the given aToken
    function balance() public view override returns (uint256) {
        (, , uint256 totalSupplied) = ILens(lens).getCurrentSupplyBalanceInOf(
            aToken,
            address(this)
        );

        return totalSupplied;
    }

    /// ------------------------------------------
    /// ------------- Helper Methods -------------
    /// ------------------------------------------

    /// @notice accrue interest in the underlying morpho venue
    function _accrueUnderlying() internal override {
        /// accrue interest in Morpho Aave
        IMorpho(morpho).updateIndexes(aToken);
    }

    /// @dev withdraw from the underlying morpho market.
    function _withdrawAndTransfer(
        uint256 amount,
        address to
    ) internal override {
        IMorpho(morpho).withdraw(aToken, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @dev deposit in the underlying morpho market.
    function _supply(uint256 amount) internal override {
        IERC20(token).approve(address(morpho), amount);
        IMorpho(morpho).supply(
            aToken, /// aToken to supply liquidity to
            address(this), /// the address of the user you want to supply on behalf of
            amount
        );
    }

    /// @dev claim rewards from the underlying aave market.
    /// returns amount of reward tokens claimed
    function _claim() internal override returns (uint256) {
        address[] memory aTokens = new address[](1);
        aTokens[0] = aToken;

        return IMorpho(morpho).claimRewards(aTokens, false); /// bool set false to receive COMP
    }
}