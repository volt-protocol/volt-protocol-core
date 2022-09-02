// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ERC20HoldingPCVDeposit
/// @notice PCVDeposit that is used to hold ERC20 tokens as a safe harbour. Deposit is a no-op
interface IERC20HoldingPCVDeposit {
    /// @notice Token which the balance is reported in
    function token() external view returns (IERC20);

    ///////   READ-ONLY Methods /////////////

    /// @notice No-op deposit
    function deposit() external;

    /// @notice Withdraw underlying
    /// @param amountUnderlying of tokens withdrawn
    /// @param to the address to send PCV to
    function withdraw(address to, uint256 amountUnderlying) external;

    /// @notice Withdraw all of underlying
    /// @param to the address to send PCV to
    function withdrawAll(address to) external;

    /// @notice Wraps all ETH held by the contract to WETH. Permissionless, anyone can call it
    function wrapETH() external;
}
