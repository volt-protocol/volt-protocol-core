// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPCVDeposit} from "./IPCVDeposit.sol";
import {PCVDeposit} from "./PCVDeposit.sol";
import {CoreRef} from "../refs/CoreRef.sol";
import {TribeRoles} from "../core/TribeRoles.sol";
import {Constants} from "../Constants.sol";
import {IERC20HoldingPCVDeposit} from "./IERC20HoldingPCVDeposit.sol";
import {MainnetAddresses} from "../test/integration/fixtures/MainnetAddresses.sol";
import {ArbitrumAddresses} from "../test/integration/fixtures/ArbitrumAddresses.sol";

/// @title ERC20HoldingPCVDeposit
/// @notice PCVDeposit that is used to hold ERC20 tokens as a safe harbour. Deposit is a no-op
contract ERC20HoldingPCVDeposit is PCVDeposit, IERC20HoldingPCVDeposit {
    using SafeERC20 for IERC20;

    /// @notice Token which the balance is reported in
    IERC20 public immutable override token;

    constructor(address _core, IERC20 _token) CoreRef(_core) {
        require(
            address(_token) != MainnetAddresses.VOLT &&
                address(_token) != ArbitrumAddresses.VOLT,
            "VOLT not supported"
        );
        token = _token;
    }

    /// @notice Empty receive function to receive ETH
    receive() external payable {}

    ///////   READ-ONLY Methods /////////////

    /// @notice returns total balance of PCV in the deposit
    function balance() public view override returns (uint256) {
        return token.balanceOf(address(this));
    }

    /// @notice returns the resistant balance and VOLT in the deposit
    function resistantBalanceAndVolt()
        public
        view
        override
        returns (uint256, uint256)
    {
        return (balance(), 0);
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
    function withdraw(address to, uint256 amountUnderlying)
        external
        override(IERC20HoldingPCVDeposit, IPCVDeposit)
        hasAnyOfTwoRoles(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER)
    {
        token.safeTransfer(to, amountUnderlying);
        emit Withdrawal(msg.sender, to, amountUnderlying);
    }

    /// @notice Withdraw all of underlying
    /// @param to the address to send PCV to
    function withdrawAll(address to)
        external
        hasAnyOfTwoRoles(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER)
    {
        uint256 amountUnderlying = token.balanceOf(address(this));
        token.safeTransfer(to, amountUnderlying);
        emit Withdrawal(msg.sender, to, amountUnderlying);
    }

    /// @notice Wraps all ETH held by the contract to WETH. Permissionless, anyone can call it
    function wrapETH() public {
        uint256 ethBalance = address(this).balance;

        if (ethBalance != 0) {
            if (block.chainid == 1) {
                Constants.WETH.deposit{value: ethBalance}();
            } else if (block.chainid == 42161) {
                Constants.ARBITRUM_WETH.deposit{value: ethBalance}();
            } else {
                revert("Can only wrap eth on mainnet and arbitrum");
            }
        }
    }
}
