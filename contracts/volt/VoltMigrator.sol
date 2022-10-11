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

    /// @notice address of the old VOLT token
    Volt public constant OLD_VOLT =
        Volt(0x559eBC30b0E58a45Cc9fF573f77EF1e5eb1b3E18);

    /// @notice address of the new VOLT token
    IVolt public immutable newVolt;

    constructor(address core, IVolt _newVolt) CoreRef(core) {
        newVolt = _newVolt;
    }

    /// @notice function to exchange old VOLT for new VOLT
    /// @param amount the amount of old VOLT user wishes to exchange
    function exchange(uint256 amount) external {
        _migrateVolt(msg.sender, amount);
    }

    /// @notice function to exchange old VOLT for new VOLT
    /// takes the minimum of users old VOLT balance, or the amount
    /// user has approved to the migrator contract & exchanges for new VOLT
    function exchangeAll() external {
        uint256 amountToExchange = Math.min(
            OLD_VOLT.balanceOf(msg.sender),
            OLD_VOLT.allowance(msg.sender, address(this))
        );
        require(amountToExchange != 0, "VoltMigrator: no amount to exchange");

        _migrateVolt(msg.sender, amountToExchange);
    }

    /// @notice function to exchange old VOLT for new VOLT
    /// @param amount the amount of old VOLT user wishes to exchange
    /// @param to address to send the new VOLT to
    function exchangeTo(address to, uint256 amount) external {
        _migrateVolt(to, amount);
    }

    /// @notice function to exchange old VOLT for new VOLT
    /// takes the minimum of users old VOLT balance, or the amount
    /// user has approved to the migrator contract & exchanges for new VOLT
    /// @param to address to send the new VOLT to
    function exchangeAllTo(address to) external {
        uint256 amountToExchange = Math.min(
            OLD_VOLT.balanceOf(msg.sender),
            OLD_VOLT.allowance(msg.sender, address(this))
        );
        require(amountToExchange != 0, "VoltMigrator: no amount to exchange");

        _migrateVolt(to, amountToExchange);
    }

    function _migrateVolt(address to, uint256 amount) internal {
        OLD_VOLT.burnFrom(msg.sender, amount);
        newVolt.transfer(to, amount);

        emit VoltMigrated(msg.sender, to, amount);
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
