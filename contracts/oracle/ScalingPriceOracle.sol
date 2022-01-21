// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./../utils/Timed.sol";
import "./../Constants.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";


import "hardhat/console.sol";

contract ScalingPriceOracle is Timed {

    using SafeCast for uint256;

    /// @notice current amount that oracle price is inflating by annually in basis points
    uint256 public currentChangeRateBasisPoints;

    /// @notice oracle price. starts off at 1e18
    uint256 public oraclePrice = 1e18;

    constructor(
        uint256 _duration,
        uint256 _currentChangeRateBasisPoints
    ) Timed(_duration) {
        currentChangeRateBasisPoints = _currentChangeRateBasisPoints;
        _initTimed();
    }
    
    /// TODO this also needs to account for deflation when the CPI goes negative...
    function getCurrentOraclePrice() public view returns (uint256) {
        return oraclePrice +
            (oraclePrice * currentChangeRateBasisPoints / Constants.BASIS_POINTS_GRANULARITY * (block.timestamp - startTime)) / Constants.ONE_YEAR;
    }

    function oneYear() public pure returns(uint256) {
        return Constants.ONE_YEAR;
    }

    function updateOraclePrice() external afterTime {
        _initTimed();

        oraclePrice = getCurrentOraclePrice();
    }
}
