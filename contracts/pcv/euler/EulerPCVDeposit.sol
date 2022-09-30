pragma solidity =0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IEToken} from "./IEToken.sol";
import {CoreRef} from "../../refs/CoreRef.sol";
import {PCVDeposit} from "../PCVDeposit.sol";

/// @notice PCV Deposit for Euler
contract EulerPCVDeposit is PCVDeposit {
    using SafeERC20 for IERC20;

    /// @notice euler main contract that receives tokens
    address public immutable eulerMain;

    /// @notice reference to the euler token that represents an asset
    IEToken public immutable eToken;

    /// @notice reference to the underlying token
    IERC20 public immutable token;

    /// @notice sub-account id for euler
    uint256 public constant subAccountId = 0;

    /// @notice fetch underlying asset by calling pool and getting liquidity asset
    /// @param _core reference to the Core contract
    /// @param _eToken reference to the euler asset token
    /// @param _eulerMain reference to the euler main address
    constructor(
        address _core,
        address _eToken,
        address _eulerMain
    ) CoreRef(_core) {
        eToken = IEToken(_eToken);
        eulerMain = _eulerMain;
        token = IERC20(IEToken(_eToken).underlyingAsset());
    }

    /// @notice return the amount of funds this contract owns in underlying tokens
    function balance() public view override returns (uint256) {
        return eToken.balanceOfUnderlying(address(this));
    }

    /// @notice return the underlying token denomination for this deposit
    function balanceReportedIn() external view returns (address) {
        return address(token);
    }

    /// @notice deposit PCV into Euler.
    function deposit() external whenNotPaused {
        uint256 amount = IERC20(token).balanceOf(address(this));
        if (amount == 0) {
            /// no op to prevent wasted gas
            return;
        }

        token.approve(eulerMain, amount);
        eToken.deposit(subAccountId, amount);

        emit Deposit(msg.sender, amount);
    }

    /// @notice withdraw PCV from Euler, only callable by PCV controller
    /// @param to destination after funds are withdrawn from venue
    /// @param amount of PCV to withdraw from the venue
    function withdraw(address to, uint256 amount)
        external
        override
        onlyPCVController
    {
        eToken.withdraw(subAccountId, amount);
        token.safeTransfer(to, amount);

        emit Withdrawal(msg.sender, to, amount);
    }

    /// @notice withdraw all PCV in this deposit from Euler, only callable by PCV controller
    /// @param to destination after funds are withdrawn from venue
    function withdrawAll(address to) external onlyPCVController {
        eToken.withdraw(subAccountId, type(uint256).max);
        uint256 amount = token.balanceOf(address(this));
        token.safeTransfer(to, amount);

        emit Withdrawal(msg.sender, to, amount);
    }
}
