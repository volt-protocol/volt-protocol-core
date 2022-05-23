// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Decimal} from "../external/Decimal.sol";
import {Constants} from "./../Constants.sol";
import {Deviation} from "./../utils/Deviation.sol";
import {ScalingPriceOracle} from "./ScalingPriceOracle.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// @notice contract that receives a chainlink price feed and then linearly interpolates that rate over
/// a 28 day period into the VOLT price. Interest is compounded monthly when the rate is updated
/// Specifically built for L2 to allow a deployment that is mid-month
/// @author Elliot Friedman
contract L2ScalingPriceOracle is ScalingPriceOracle {
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
    ) ScalingPriceOracle(_oracle, _jobid, _fee, _currentMonth, _previousMonth) {
        /// ensure start time is not more than 28 days ago
        require(
            _actualStartTime > block.timestamp - TIMEFRAME,
            "L2ScalingPriceOracle: Start time too far in the past"
        );
        startTime = _actualStartTime;

        /// ensure starting oracle price is greater than or equal to 1
        require(
            _startingOraclePrice >= 1e18,
            "L2ScalingPriceOracle: Starting oracle price too low"
        );
        oraclePrice = _startingOraclePrice;
    }
}
