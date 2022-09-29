pragma solidity =0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ILens} from "./ILens.sol";
import {IMorpho} from "./IMorpho.sol";
import {ICompoundOracle, ICToken} from "./ICompound.sol";
import {CoreRef} from "../../refs/CoreRef.sol";
import {PCVDeposit} from "../PCVDeposit.sol";

/// @notice PCV Deposit for Morpho-Compound V2.
/// Implements the PCV Deposit interface to deposit and withdraw funds in Morpho
/// Liquidity profile of Morpho for this deposit is fully liquid for USDC and DAI
/// because the incentivized rates are higher than the P2P rate.
/// Only for depositing USDC and DAI. USDT is not in scope
contract MorphoCompoundPCVDeposit is PCVDeposit {
    using SafeERC20 for IERC20;

    /// @notice reference to the lens contract for morpho-compound v2
    address public constant LENS = 0x930f1b46e1D081Ec1524efD95752bE3eCe51EF67;

    /// @notice reference to the morpho-compound v2 market
    address public constant MORPHO = 0x8888882f8f843896699869179fB6E4f7e3B58888;

    /// @notice reference to underlying token
    address public immutable token;

    /// @notice reference to cToken used in Morpho
    address public immutable cToken;

    constructor(address _core, address _cToken) CoreRef(_core) {
        cToken = _cToken;
        token = ICToken(_cToken).underlying();
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
    function deposit() public {
        uint256 amount = IERC20(token).balanceOf(address(this));
        if (amount == 0) {
            /// no op to prevent revert on empty deposit
            return;
        }

        IERC20(token).approve(MORPHO, amount);
        IMorpho(MORPHO).supply(
            cToken, /// cToken to supply liquidity to
            address(this), /// the address of the user you want to supply on behalf of
            amount
        );

        emit Deposit(msg.sender, amount);
    }

    /// @notice withdraw tokens from the PCV allocation
    /// @param to the address PCV will be sent to
    /// @param amount of tokens withdrawn
    function withdraw(address to, uint256 amount) external onlyPCVController {
        IMorpho(MORPHO).withdraw(cToken, amount);
        IERC20(token).safeTransfer(to, amount);

        emit Withdrawal(msg.sender, to, amount);
    }
}
