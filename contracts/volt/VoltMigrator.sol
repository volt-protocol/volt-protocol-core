//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {CoreRef} from "../refs/CoreRef.sol";
import {Volt} from "./Volt.sol";
import {IVolt} from "./IVolt.sol";
import {IVoltMigrator} from "./IVoltMigrator.sol";

/// @title Volt Migrator
/// @notice This contract is used to allow user to migrate from the old VOLT token
/// to the new VOLT token that will be able to participate in the Volt Veto Module.
/// users will deposit their old VOLT token which'll be burnt, and the new Volt token
/// will be minted to them.
contract VoltMigrator is IVoltMigrator, CoreRef {
    using SafeERC20 for IERC20;
    // solhint-disable-next-line const-name-snakecase
    Volt public constant oldVolt =
        Volt(0x559eBC30b0E58a45Cc9fF573f77EF1e5eb1b3E18);
    // solhint-disable-next-line const-name-snakecase
    IVolt public constant newVolt =
        IVolt(0x559eBC30b0E58a45Cc9fF573f77EF1e5eb1b3E18);

    constructor(address core) CoreRef(core) {}

    /// @notice function to exchange old VOLT for new VOLT
    /// @param amount the amount of old VOLT user wishes to exchange
    function exchange(uint256 amount) external {
        oldVolt.burnFrom(msg.sender, amount);
        newVolt.transfer(msg.sender, amount);
    }

    /// @notice function to exchange old VOLT for new VOLT
    /// takes the minimum of users old VOLT balance, or the amount
    /// user has approved to the migrator contract & exchanges for new VOLT
    function exchangeAll() external {
        uint256 amountToExchange = Math.min(
            oldVolt.balanceOf(msg.sender),
            oldVolt.allowance(msg.sender, address(this))
        );

        oldVolt.burnFrom(msg.sender, amountToExchange);
        newVolt.transfer(msg.sender, amountToExchange);
    }

    /// @notice sweep target token,
    /// @param token to sweep
    /// @param to recipient
    /// @param amount of token to be sent
    function sweep(
        address token,
        address to,
        uint256 amount
    ) external onlyGovernor {
        IERC20(token).safeTransfer(to, amount);
    }
}
