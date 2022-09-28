// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IOracle} from "./IOracle.sol";
import {CoreRef} from "../refs/CoreRef.sol";
import {Decimal} from "../external/Decimal.sol";
import {OraclePassThrough} from "./OraclePassThrough.sol";
import {AggregatorV3Interface} from "../external/AggregatorV3Interface.sol";
import {ChainlinkOracleWrapper} from "./ChainlinkOracleWrapper.sol";

/// @title Composite Chainlink Oracle wrapper
/// @author Elliot Friedman
/// @notice Reads a Chainlink oracle value & wrap it under the standard Fei oracle interface
contract CompositeChainlinkOracleWrapper is ChainlinkOracleWrapper {
    using Decimal for Decimal.D256;

    /// @notice the oracle pass through to get the current Volt price
    OraclePassThrough public immutable oraclePassThrough;

    /// @notice scaling factor to divide Volt price by
    uint256 public constant scalingFactor = 1e18;

    /// @notice ChainlinkOracleWrapper constructor
    /// @param _core Volt Core for reference
    /// @param _chainlinkOracle reference to the target Chainlink oracle
    /// @param _oraclePassThrough contract to get the Volt price
    /// @dev decimals of the oracle are expected to never change, if Chainlink
    /// updates that behavior in the future, we might consider reading the
    /// oracle decimals() on every read() call.
    constructor(
        address _core,
        address _chainlinkOracle,
        OraclePassThrough _oraclePassThrough
    ) ChainlinkOracleWrapper(_core, _chainlinkOracle) {
        oraclePassThrough = _oraclePassThrough;
    }

    /// @notice read the oracle price in Volt terms
    /// @return oracle price of token priced in Volt
    /// @return true if price is valid
    function read() external view override returns (Decimal.D256 memory, bool) {
        (
            uint80 roundId,
            int256 price,
            ,
            ,
            uint80 answeredInRound
        ) = chainlinkOracle.latestRoundData();
        bool valid = !paused() && price > 0 && answeredInRound == roundId;
        uint256 voltPrice = oraclePassThrough.getCurrentOraclePrice();

        /// multiply then divide
        Decimal.D256 memory value = Decimal
            .from(uint256(price))
            .mul(scalingFactor)
            .div(oracleDecimalsNormalizer)
            .div(voltPrice);
        return (value, valid);
    }
}
