// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {CoreRef} from "../refs/CoreRef.sol";
import {IPCVDepositV2} from "./IPCVDepositV2.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {TribeRoles} from "../core/TribeRoles.sol";

/// @title abstract contract for withdrawing ERC-20 tokens using a PCV Controller
/// @author VOLT Protocol
abstract contract PCVDepositV2 is IPCVDepositV2, CoreRef {
    using SafeERC20 for IERC20;
    using Address for address;

    /// @notice withdraw ERC20 from the contract
    /// @param token address of the ERC20 to send
    /// @param to address destination of the ERC20
    /// @param amount quantity of ERC20 to send
    function withdrawERC20(
        address token,
        address to,
        uint256 amount
    )
        public
        virtual
        override
        hasAnyOfTwoRoles(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER)
    {
        _withdrawERC20(token, to, amount);
    }

    /// @notice withdraw All ERC20 from the contract
    /// @param token address of the ERC20 to send
    /// @param to address destination of the ERC20
    function withdrawAllERC20(address token, address to)
        public
        virtual
        override
        hasAnyOfTwoRoles(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER)
    {
        uint256 amount = IERC20(token).balanceOf(address(this));
        _withdrawERC20(token, to, amount);
    }

    function _withdrawERC20(
        address token,
        address to,
        uint256 amount
    ) internal {
        IERC20(token).safeTransfer(to, amount);
        emit WithdrawERC20(msg.sender, token, to, amount);
    }

    /// @notice withdraw ETH from the contract
    /// @param to address to send ETH
    /// @param amountOut amount of ETH to send
    function withdrawETH(address payable to, uint256 amountOut)
        external
        virtual
        override
        hasAnyOfTwoRoles(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER)
    {
        to.transfer(amountOut); /// only forward 2300 gas to recipient
        emit WithdrawETH(msg.sender, to, amountOut);
    }

    function balance() public view virtual override returns (uint256);

    function resistantBalanceAndVolt()
        public
        view
        virtual
        override
        returns (uint256, uint256)
    {
        return (balance(), 0);
    }
}
