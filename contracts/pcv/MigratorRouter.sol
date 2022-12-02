// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IMigratorRouter} from "./IMigratorRouter.sol";
import {IPegStabilityModule} from "../peg/IPegStabilityModule.sol";
import {IVolt} from "../volt/IVolt.sol";
import {IVoltMigrator} from "../volt/IVoltMigrator.sol";

/// @title Migrator Router
/// @notice This contract is a router that wraps around the token migrator from
/// the old volt ERC20 token to the new ERC20 token, to allow users to redeem for
/// stables using the old volt version once the new version is live
contract MigratorRouter is IMigratorRouter {
    /// @notice the old VOLT token
    IVolt public constant OLD_VOLT =
        IVolt(0x559eBC30b0E58a45Cc9fF573f77EF1e5eb1b3E18);

    /// @notice VOLT-DAI PSM to swap between the two assets
    IPegStabilityModule public immutable daiPSM;

    /// @notice VOLT-USDC PSM to swap between the two assets
    IPegStabilityModule public immutable usdcPSM;

    /// @notice address of the new VOLT token
    IVolt public immutable newVolt;

    /// @notice the VOLT migrator contract to swap from old VOLT to new
    IVoltMigrator public immutable voltMigrator;

    constructor(
        IVolt _newVolt,
        IVoltMigrator _voltMigrator,
        IPegStabilityModule _daiPSM,
        IPegStabilityModule _usdcPSM
    ) {
        newVolt = _newVolt;
        voltMigrator = _voltMigrator;

        daiPSM = _daiPSM;
        usdcPSM = _usdcPSM;

        /// It's safe to give the following contracts max approval as they
        /// are part of the Volt system and therefore we can be very confident
        /// in their behavior, as such the scope of attack of giving the following
        /// contracts max approvals is very limited. Also the only time the migrator
        /// contract uses the transferFrom it passes msg.sender, so the only way to spend
        /// the approval is via the person who gave the approval requesting the transfer
        OLD_VOLT.approve(address(voltMigrator), type(uint256).max);
        newVolt.approve(address(daiPSM), type(uint256).max);
        newVolt.approve(address(usdcPSM), type(uint256).max);
    }

    /// @notice This lets the user redeem DAI using old VOLT
    /// @param amountVoltIn the amount of old VOLT being deposited
    /// @param minAmountOut the minimum amount of DAI the user expects to receive
    function redeemDai(
        uint256 amountVoltIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut) {
        OLD_VOLT.transferFrom(msg.sender, address(this), amountVoltIn);
        voltMigrator.exchange(amountVoltIn);

        amountOut = daiPSM.redeem(msg.sender, amountVoltIn, minAmountOut);
    }

    /// @notice This lets the user redeem USDC using old VOLT
    /// @param amountVoltIn the amount of old VOLT being deposited
    /// @param minAmountOut the minimum amount of USDC the user expects to receive
    function redeemUSDC(
        uint256 amountVoltIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut) {
        OLD_VOLT.transferFrom(msg.sender, address(this), amountVoltIn);
        voltMigrator.exchange(amountVoltIn);

        amountOut = usdcPSM.redeem(msg.sender, amountVoltIn, minAmountOut);
    }
}
