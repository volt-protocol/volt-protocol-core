//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Withdrawer {
    using SafeERC20 for IERC20;

    function _transferAllToken(address to, address token) internal {
        IERC20(token).transfer(to, IERC20(token).balanceOf(address(this)));
    }
}
