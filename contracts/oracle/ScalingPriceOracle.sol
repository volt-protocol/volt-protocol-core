// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./../utils/Timed.sol";
import "./../Constants.sol";
import "./IScalingPriceOracle.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "hardhat/console.sol";

contract ScalingPriceOracle is Timed, IScalingPriceOracle {
    using SafeCast for *;

    /// @notice current amount that oracle price is inflating/deflating by annually in basis points
    int256 public override annualChangeRateBasisPoints;

    /// @notice oracle price. starts off at 1e18
    uint256 public oraclePrice = 1e18;

    constructor(uint256 _duration, int256 _annualChangeRateBasisPoints)
        Timed(_duration)
    {
        annualChangeRateBasisPoints = _annualChangeRateBasisPoints;
        _initTimed();
    }

    /// @notice get the current scaled oracle price
    function getCurrentOraclePrice() public view override returns (uint256) {
        return
            SafeCast.toUint256(
                oraclePrice.toInt256() +
                    (((oraclePrice.toInt256() * annualChangeRateBasisPoints) /
                        Constants.BASIS_POINTS_GRANULARITY.toInt256()) *
                        (block.timestamp - startTime).toInt256()) /
                    Constants.ONE_YEAR.toInt256()
            );
    }

    /// @notice internal helper method to lock in the current price.
    /// should only be used when changing the oracle price to a higher price
    function _updateOraclePrice() internal afterTime {
        _initTimed();

        oraclePrice = getCurrentOraclePrice();
    }
}
