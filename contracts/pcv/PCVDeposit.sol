// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {IPCVDeposit} from "./IPCVDeposit.sol";

/// @title abstract contract for withdrawing ERC-20 tokens using a PCV Controller
/// @author Fei Protocol
abstract contract PCVDeposit is IPCVDeposit, CoreRefV2 {
    using SafeERC20 for IERC20;

    /// @notice withdraw ERC20 from the contract
    /// @param token address of the ERC20 to send
    /// @param to address destination of the ERC20
    /// @param amount quantity of ERC20 to send
    function withdrawERC20(
        address token,
        address to,
        uint256 amount
    ) public virtual override onlyPCVController {
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
    function withdrawETH(
        address payable to,
        uint256 amountOut
    ) external virtual override onlyPCVController {
        Address.sendValue(to, amountOut);
        emit WithdrawETH(msg.sender, to, amountOut);
    }

    function balance() public view virtual override returns (uint256);
}
