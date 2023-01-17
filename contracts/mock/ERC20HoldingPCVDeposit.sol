// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IWETH} from "../external/IWETH.sol";
import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {VoltRoles} from "../core/VoltRoles.sol";
import {PCVDeposit} from "./../pcv/PCVDeposit.sol";
import {IPCVDeposit} from "./../pcv/IPCVDeposit.sol";
import {IERC20HoldingPCVDeposit} from "./IERC20HoldingPCVDeposit.sol";

/// @title ERC20HoldingPCVDeposit
/// @notice PCVDeposit that is used to hold ERC20 tokens as a safe harbour. Deposit is a no-op

/// DO NOT USE in prod, still needs multiple code reviews. Contract is only for testing currently

contract ERC20HoldingPCVDeposit is PCVDeposit, IERC20HoldingPCVDeposit {
    using SafeERC20 for IERC20;

    /// @notice Token which the balance is reported in
    IERC20 public immutable override token;

    /// @notice WETH contract
    IWETH public immutable weth;

    constructor(address _core, IERC20 _token, address _weth) CoreRefV2(_core) {
        token = _token;
        weth = IWETH(_weth);
    }

    /// @notice Empty receive function to receive ETH
    receive() external payable {}

    ///////   READ-ONLY Methods /////////////

    /// @notice returns total balance of PCV in the deposit
    function balance() public view override returns (uint256) {
        return token.balanceOf(address(this));
    }

    /// @notice display the related token of the balance reported
    function balanceReportedIn() public view override returns (address) {
        return address(token);
    }

    /// @notice No-op deposit
    function deposit()
        external
        override(IERC20HoldingPCVDeposit, IPCVDeposit)
        whenNotPaused
    {}

    /// @notice Withdraw underlying
    /// @param amountUnderlying of tokens withdrawn
    /// @param to the address to send PCV to
    function withdraw(
        address to,
        uint256 amountUnderlying
    )
        external
        override(IERC20HoldingPCVDeposit, IPCVDeposit)
        hasAnyOfTwoRoles(VoltRoles.GOVERNOR, VoltRoles.PCV_CONTROLLER)
    {
        token.safeTransfer(to, amountUnderlying);
        emit Withdrawal(msg.sender, to, amountUnderlying);
    }

    /// @notice Withdraw all of underlying
    /// @param to the address to send PCV to
    function withdrawAll(
        address to
    ) external hasAnyOfTwoRoles(VoltRoles.GOVERNOR, VoltRoles.PCV_CONTROLLER) {
        uint256 amountUnderlying = token.balanceOf(address(this));
        token.safeTransfer(to, amountUnderlying);
        emit Withdrawal(msg.sender, to, amountUnderlying);
    }

    /// @notice Wraps all ETH held by the contract to WETH. Permissionless, anyone can call it
    function wrapETH() public {
        uint256 ethBalance = address(this).balance;

        if (ethBalance != 0) {
            weth.deposit{value: ethBalance}();
        }
    }
}
