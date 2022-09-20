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
    IVolt public constant oldVolt =
        IVolt(0x559eBC30b0E58a45Cc9fF573f77EF1e5eb1b3E18);

    IPegStabilityModule public immutable daiPSM;
    IPegStabilityModule public immutable usdcPSM;

    /// @notice the VOLT migrator contract
    // IVoltMigrator public constant voltMigrator =
    //     IVoltMigrator(0x559eBC30b0E58a45Cc9fF573f77EF1e5eb1b3E18); // fill with correct address once deployed

    // IVolt public constant newVolt =
    //     IVolt(0x559eBC30b0E58a45Cc9fF573f77EF1e5eb1b3E18);

    /// new PSMS will be deployed will replace these addresses once they have been dpeloyed

    /// @notice the VOLT-DAI PSM to swap between the two assets
    // IPegStabilityModule public constant daiPSM =
    //     IPegStabilityModule(0x42ea9cC945fca2dfFd0beBb7e9B3022f134d9Bdd);

    // /// @notice the VOLT-USDC PSM to swap between the two assets
    // IPegStabilityModule public constant usdcPSM =
    //     IPegStabilityModule(0x0b9A7EA2FCA868C93640Dd77cF44df335095F501);

    address public immutable newVolt;
    address public voltMigrator;

    constructor(
        address _newVolt,
        address _voltMigrator,
        IPegStabilityModule _daiPSM,
        IPegStabilityModule _usdcPSM
    ) {
        newVolt = _newVolt;
        voltMigrator = _voltMigrator;

        daiPSM = _daiPSM;
        usdcPSM = _usdcPSM;
    }

    /// @notice This lets the user redeem DAI using old VOLT
    /// @param amountVoltIn the amount of old VOLT being deposited
    /// @param minAmountOut the minimum amount of DAI the user expects to receive
    function redeemDai(uint256 amountVoltIn, uint256 minAmountOut) external {
        oldVolt.transferFrom(msg.sender, address(this), amountVoltIn);
        IVoltMigrator(voltMigrator).exchange(amountVoltIn);

        daiPSM.redeem(msg.sender, amountVoltIn, minAmountOut);
    }

    /// @notice This lets the user redeem USDC using old VOLT
    /// @param amountVoltIn the amount of old VOLT being deposited
    /// @param minAmountOut the minimum amount of USDC the user expects to receive
    function redeemUSDC(uint256 amountVoltIn, uint256 minAmountOut) external {
        oldVolt.transferFrom(msg.sender, address(this), amountVoltIn);
        IVoltMigrator(voltMigrator).exchange(amountVoltIn);

        usdcPSM.redeem(msg.sender, amountVoltIn, minAmountOut);
    }
}
