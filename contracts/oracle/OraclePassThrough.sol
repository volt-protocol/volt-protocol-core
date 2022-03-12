// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Decimal} from "../external/Decimal.sol";
import {CoreRef} from "./../refs/CoreRef.sol";
import {ScalingPriceOracle} from "./ScalingPriceOracle.sol";
import {IOraclePassThrough} from "./IOraclePassThrough.sol";

/// @notice contract that passes all price calls to the Scaling Price Oracle
/// The Scaling Price Oracle can be changed if there is a decision to change how data is interpolated
/// without needing all contracts in the system to be upgraded, only this contract will have to change where it points
contract OraclePassThrough is CoreRef, IOraclePassThrough {
    using Decimal for Decimal.D256;

    /// @notice reference to the scaling price oracle
    ScalingPriceOracle public override scalingPriceOracle;

    /// @notice event emitted when the scaling price oracle is updated
    event ScalingPriceOracleUpdate(
        ScalingPriceOracle oldScalingPriceOracle,
        ScalingPriceOracle newScalingPriceOracle
    );

    constructor(address coreAddress, ScalingPriceOracle _scalingPriceOracle)
        CoreRef(coreAddress)
    {
        scalingPriceOracle = _scalingPriceOracle;
    }

    /// @notice updates the oracle price
    /// @dev no-op, ScalingPriceOracle is updated automatically
    /// added for backwards compatibility with OracleRef
    function update() public {}

    // ----------- Getters -----------

    /// @notice function to get the current oracle price for the OracleRef contract
    function read()
        external
        view
        override
        returns (Decimal.D256 memory price, bool valid)
    {
        uint256 currentPrice = scalingPriceOracle.getCurrentOraclePrice();

        price = Decimal.from(currentPrice).div(1 ether);
        valid = true;
    }

    /// @notice function to get the current oracle price for the entire system
    function getCurrentOraclePrice() external view override returns (uint256) {
        return scalingPriceOracle.getCurrentOraclePrice();
    }

    // ----------- Governor only state changing api -----------

    /// @notice function to update the scaling price oracle reference
    /// @param newScalingPriceOracle the new oracle to reference
    function updateScalingPriceOracle(ScalingPriceOracle newScalingPriceOracle)
        external
        override
        onlyGovernor
    {
        ScalingPriceOracle oldScalingPriceOracle = scalingPriceOracle;
        scalingPriceOracle = newScalingPriceOracle;

        emit ScalingPriceOracleUpdate(
            oldScalingPriceOracle,
            newScalingPriceOracle
        );
    }
}
