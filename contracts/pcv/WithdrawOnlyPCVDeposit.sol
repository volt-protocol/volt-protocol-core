// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {IERC20, PCVDeposit, CoreRef} from "./PCVDeposit.sol";

/// @title ERC20 token deposit contract that allows for withdrawing
/// of ERC-20 tokens using a PCV Controller
/// Meant to slot into the current Volt system to allow users to redeem
/// volt for FEI through the Non Custodial PSM
/// @author Elliot Friedman
contract WithdrawOnlyPCVDeposit is PCVDeposit {
    /// @notice the token underlying the cToken
    IERC20 public immutable token;

    constructor(address _core, IERC20 _token) CoreRef(_core) {
        token = _token;
    }

    /// @notice reverts to ensure deposit cannot be called
    function deposit() external override {
        revert("WithdrawOnlyPCVDeposit: deposit not allowed");
    }

    /// @notice withdraw ERC20 from the contract
    /// @param to address destination of the ERC20
    /// @param amount quantity of ERC20 to send
    function withdraw(address to, uint256 amount)
        public
        override
        onlyPCVController
    {
        _withdrawERC20(address(token), to, amount);
    }

    /// @notice return the balance of the underlying token in this PCV Deposit
    function balance() public view override returns (uint256) {
        return token.balanceOf(address(this));
    }

    /// @notice display the related token of the balance reported
    function balanceReportedIn() public view override returns (address) {
        return address(token);
    }
}
