// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IOracle} from "./IOracle.sol";
import {CoreRef} from "../refs/CoreRef.sol";
import {Decimal} from "../external/Decimal.sol";
import {AggregatorV3Interface} from "../external/AggregatorV3Interface.sol";

/// @title Chainlink oracle wrapper
/// @author eswak, Elliot
/// @notice Reads a Chainlink oracle value & wrap it under the standard Volt oracle interface
contract ChainlinkOracleWrapper is IOracle, CoreRef {
    using Decimal for Decimal.D256;

    /// @notice the referenced chainlink oracle
    AggregatorV3Interface public immutable chainlinkOracle;

    /// @notice number to divide answer from chainlink by
    uint256 public immutable oracleDecimalsNormalizer;

    /// @notice ChainlinkOracleWrapper constructor
    /// @param _core Volt Core for reference
    /// @param _chainlinkOracle reference to the target Chainlink oracle
    /// @dev decimals of the oracle are expected to never change, if Chainlink
    /// updates that behavior in the future, we might consider reading the
    /// oracle decimals() on every read() call.
    constructor(address _core, address _chainlinkOracle) CoreRef(_core) {
        chainlinkOracle = AggregatorV3Interface(_chainlinkOracle);

        uint8 oracleDecimals = chainlinkOracle.decimals();
        oracleDecimalsNormalizer = 10**uint256(oracleDecimals);
    }

    /// @notice updates the oracle price
    /// @dev no-op, Chainlink is updated automatically
    function update() external view override whenNotPaused {}

    /// @notice determine if read value is stale
    /// @return true if read value is stale
    function isOutdated() external view override returns (bool) {
        (uint80 roundId, , , , uint80 answeredInRound) = chainlinkOracle
            .latestRoundData();
        return answeredInRound != roundId;
    }

    /// @notice read the oracle price
    /// @return oracle price
    /// @return true if price is valid
    function read()
        external
        view
        virtual
        override
        returns (Decimal.D256 memory, bool)
    {
        (
            uint80 roundId,
            int256 price,
            ,
            ,
            uint80 answeredInRound
        ) = chainlinkOracle.latestRoundData();
        bool valid = !paused() && price > 0 && answeredInRound == roundId;

        /// Decimal.from scales up price by 18 decimals,
        /// then we divide it down by the amount of decimals it has with oracleDecimalsNormalizer
        /// this means the price is scaled up by 1e18 now
        Decimal.D256 memory value = Decimal.from(uint256(price)).div(
            oracleDecimalsNormalizer
        );
        return (value, valid);
    }
}
