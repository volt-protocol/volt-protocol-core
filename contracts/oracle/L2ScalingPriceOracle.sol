// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Decimal} from "../external/Decimal.sol";
import {Constants} from "./../Constants.sol";
import {Deviation} from "./../utils/Deviation.sol";
import {ScalingPriceOracle} from "./ScalingPriceOracle.sol";
import {IL2ScalingPriceOracle} from "./IL2ScalingPriceOracle.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// @notice contract that receives a chainlink price feed and then linearly interpolates that rate over
/// a 28 day period into the VOLT price. Interest is compounded monthly when the rate is updated
/// Specifically built for L2 to allow a deployment that is mid-month
/// @author Elliot Friedman
contract L2ScalingPriceOracle is
    ScalingPriceOracle,
    IL2ScalingPriceOracle,
    Ownable,
    Initializable
{
    using SafeCast for *;
    using Deviation for *;
    using Decimal for Decimal.D256;

    /// @notice maximum allowable deviation between current and new oracle price the owner sets
    /// Owner can only adjust the price in either direction a maximum of 1%
    uint256 public constant override MAX_OWNER_SYNC_DEVIATION = 100;

    /// @param _oracle address of chainlink data provider
    /// @param _jobid job id
    /// @param _fee maximum fee paid to chainlink data provider
    /// @param _currentMonth current month's inflation data
    /// @param _previousMonth previous month's inflation data
    /// @param _actualStartTime unix timestamp of Oracle Price interpolation starting time
    /// @param _startingOraclePrice starting oracle price
    constructor(
        address _oracle,
        bytes32 _jobid,
        uint256 _fee,
        uint128 _currentMonth,
        uint128 _previousMonth,
        uint256 _actualStartTime,
        uint256 _startingOraclePrice
    )
        Ownable()
        Initializable()
        ScalingPriceOracle(_oracle, _jobid, _fee, _currentMonth, _previousMonth)
    {
        /// ensure start time is not more than 28 days ago
        require(
            _actualStartTime > block.timestamp - TIMEFRAME,
            "L2ScalingPriceOracle: Start time too far in the past"
        );
        _setStartTime(_actualStartTime);

        /// ensure starting oracle price is greater than or equal to 1
        require(
            _startingOraclePrice >= 1e18,
            "L2ScalingPriceOracle: Starting oracle price too low"
        );
        oraclePrice = _startingOraclePrice;
    }

    /// @notice function to set the oracle price and sync with Eth L1 Oracle Price
    /// if the new oracle price is more than 1% away from the current stored Oracle Price,
    /// update is not allowed
    /// this function can only be called once to prevent the owner from having too much
    /// power over the system
    /// @param newOraclePrice the new oracle price to sync the starting price between L1 and L2
    function ownerSyncOraclePrice(uint256 newOraclePrice)
        external
        onlyOwner
        initializer
    {
        uint256 currentOraclePrice = oraclePrice;
        require(
            MAX_OWNER_SYNC_DEVIATION.isWithinDeviationThreshold(
                currentOraclePrice.toInt256(),
                newOraclePrice.toInt256()
            ),
            "L2ScalingPriceOracle: Oracle Price Sync outside of max deviation"
        );
        uint256 oldOraclePrice = oraclePrice;
        oraclePrice = newOraclePrice;

        emit OraclePriceUpdate(oldOraclePrice, newOraclePrice);
    }
}
