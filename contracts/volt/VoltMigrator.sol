//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {CoreRef} from "../refs/CoreRef.sol";
import {IVolt} from "./IVolt.sol";
import {IVoltMigrator} from "./IVoltMigrator.sol";
import {MainnetAddresses} from "../test/integration/fixtures/MainnetAddresses.sol";

/// @title Volt Migrator
/// @notice This contract is used to allow user to migrate from the old VOLT token
/// to the new VOLT token that will be able to participate in the Volt Veto Module.
/// users will deposit their old VOLT token which'll be burnt, and the new Volt token
/// will be minted and transferred to them.
contract VoltMigrator is CoreRef, IVoltMigrator {
    using SafeERC20 for IERC20;

    IVolt constant oldVolt = IVolt(0x559eBC30b0E58a45Cc9fF573f77EF1e5eb1b3E18);

    IERC20 constant newVolt =
        IERC20(0x559eBC30b0E58a45Cc9fF573f77EF1e5eb1b3E18);

    constructor(address core) CoreRef(core) {}

    /// @notice function to exchange old VOLT for new VOLT
    /// @param amount the amount of old VOLT user wishes to exchange
    function exchange(uint256 amount) external {
        oldVolt.transferFrom(msg.sender, address(this), amount);
        oldVolt.burn(amount);

        newVolt.mint(amount);
        newVolt.safeTransfer(msg.sender, amount);
    }

    /// @notice function to exchange old VOLT for new VOLT
    /// takes the minimum of users old VOLT balance, or the amount
    /// user has approved to the migrator contract & exchanges for new VOLT
    function exchangeAll() external {
        uint256 amountToExchange = Math.min(
            oldVolt.balanceOf(msg.sender),
            oldVolt.allowance(msg.sender, address(this))
        );

        oldVolt.burn(amountToExchange);

        newVolt.mint(amountToExchange);
        newVolt.safeTransfer(msg.sender, amountToExchange);
    }
}
