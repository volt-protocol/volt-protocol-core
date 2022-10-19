// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ILens} from "./ILens.sol";
import {IMorpho} from "./IMorpho.sol";
import {CoreRef} from "../../refs/CoreRef.sol";
import {PCVDeposit} from "../PCVDeposit.sol";
import {ICompoundOracle, ICToken} from "./ICompound.sol";

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
contract MorphoCompoundPCVDeposit is PCVDeposit {
    using SafeERC20 for IERC20;

    /// @notice reference to the lens contract for morpho-compound v2
    address public constant LENS = 0x930f1b46e1D081Ec1524efD95752bE3eCe51EF67;

    /// @notice reference to the morpho-compound v2 market
    IMorpho public constant MORPHO =
        IMorpho(0x8888882f8f843896699869179fB6E4f7e3B58888);

    /// @notice reference to underlying token
    address public immutable token;

    /// @notice cToken in compound this deposit tracks
    /// used to inform morpho about the desired market to supply liquidity
    address public immutable cToken;

    constructor(
        address _core,
        address _cToken,
        address _underlying
    ) CoreRef(_core) {
        cToken = _cToken;
        token = _underlying;
    }

    /// @notice Returns the distribution of assets supplied by this contract through Morpho-Compound.
    /// @return sum of suppliedP2P and suppliedOnPool for the given CToken
    function balance() public view override returns (uint256) {
        (, , uint256 totalSupplied) = ILens(LENS).getCurrentSupplyBalanceInOf(
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
    function deposit() public whenNotPaused {
        uint256 amount = IERC20(token).balanceOf(address(this));
        if (amount == 0) {
            /// no op to prevent revert on empty deposit
            return;
        }

        IERC20(token).approve(address(MORPHO), amount);
        MORPHO.supply(
            cToken, /// cToken to supply liquidity to
            address(this), /// the address of the user you want to supply on behalf of
            amount
        );
        
        // increment tracked deposited amount
        depositedAmount += amount;

        emit Deposit(msg.sender, amount);
    }

    /// @notice withdraw tokens from the PCV allocation
    /// @param to the address PCV will be sent to
    /// @param amount of tokens withdrawn
    function withdraw(address to, uint256 amount) external onlyPCVController {
        _withdraw(to, amount);
    }

    /// @notice withdraw all tokens from Morpho
    /// @param to the address PCV will be sent to
    function withdrawAll(address to) external onlyPCVController {
        uint256 amount = balance();
        _withdraw(to, amount);
    }

    /// @notice helper function to avoid repeated code in withdraw and withdrawAll
    function _withdraw(address to, uint256 amount) private {
        // compute profit from interests and emit an event
        uint256 _depositedAmount = depositedAmount; // SLOAD
        uint256 _balance = balance();
        uint256 profit = _balance - _depositedAmount;
        emit Harvest(address(token), int256(profit), block.timestamp);
    
        MORPHO.withdraw(cToken, amount);
        IERC20(token).safeTransfer(to, amount);
        
        // update tracked deposit amount
        depositedAmount = _balance - amount;

        emit Withdrawal(msg.sender, to, amount);
    }

    /// @notice claim COMP rewards for supplying to Morpho
    function harvest() external {
        address[] memory cTokens = new address[](1);
        cTokens[0] = cToken;

        /// set swap comp to morpho flag false to claim comp rewards
        uint256 claimedAmount = MORPHO.claimRewards(cTokens, false);

        emit Harvest(COMP, int256(claimedAmount), block.timestamp);
    }
}
