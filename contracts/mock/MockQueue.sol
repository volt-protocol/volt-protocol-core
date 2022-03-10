// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./../oracle/ChainlinkOracle.sol";

contract MockQueue is ChainlinkOracle {
    constructor(
        IScalingPriceOracle _voltOracle,
        address _oracle,
        bytes32 _jobid,
        uint256 _fee,
        uint128 _currentMonth,
        uint128 _previousMonth
    )
        ChainlinkOracle(
            _voltOracle,
            _oracle,
            _jobid,
            _fee,
            _currentMonth,
            _previousMonth
        )
    {}

    function addNewMonth(uint128 elem) external returns (bool) {
        _addNewMonth(elem);

        return true;
    }
}
