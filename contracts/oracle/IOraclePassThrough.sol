// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Decimal} from "../external/Decimal.sol";
import {ScalingPriceOracle} from "./ScalingPriceOracle.sol";

/// @notice interface to get data from the Scaling Price Oracle
interface IOraclePassThrough {

    // ----------- Getters -----------

    /// @notice reference to the scaling price oracle
    function scalingPriceOracle() external view returns (ScalingPriceOracle);

    /// @notice function to get the current oracle price for the OracleRef contract
    function read() external view returns (Decimal.D256 memory price, bool valid);

    /// @notice function to get the current oracle price for the entire system
    function getCurrentOraclePrice() external view returns (uint256);

    // ----------- Governor only state changing api -----------

    function updateScalingPriceOracle(ScalingPriceOracle newScalingPriceOracle) external;
}
