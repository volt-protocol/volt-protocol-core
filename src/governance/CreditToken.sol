// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {CoreRefV2} from "@voltprotocol/refs/CoreRefV2.sol";
import {VoltRoles} from "@voltprotocol/core/VoltRoles.sol";

/** 
@title  CREDIT ERC20 Token
@author eswak
@notice This is the debt token of the Ethereum Credit Guild.
*/
contract CreditToken is CoreRefV2, ERC20Burnable {
    constructor(
        address _core
    ) CoreRefV2(_core) ERC20("Ethereum Credit Guild - CREDIT", "CREDIT") {}

    /// @notice mint new tokens to the target address
    function mint(
        address to,
        uint256 amount
    ) external onlyVoltRole(VoltRoles.CREDIT_MINTER) {
        _mint(to, amount);
    }
}
