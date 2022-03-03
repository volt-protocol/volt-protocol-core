// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

contract MockScalingPriceOracle {
    uint256 currentOraclePrice;
    int256 changeRateBasisPoints;
    address chainlinkOracle;

    constructor(
        uint256 _currentOraclePrice,
        int256 _changeRateBasisPoints,
        address _chainlinkOracle
    ) {
        currentOraclePrice = _currentOraclePrice;
        changeRateBasisPoints = _changeRateBasisPoints;
        chainlinkOracle = _chainlinkOracle;
    }

    function getCurrentOraclePrice() external view returns (uint256) {
        return currentOraclePrice;
    }

    function annualChangeRateBasisPoints() external view returns (int256) {
        return changeRateBasisPoints;
    }

    function chainlinkCPIOracle() external view returns (address) {
        return chainlinkOracle;
    }

    function oracleUpdateChangeRate(int256 newChangeRateBasisPoints) external {
        changeRateBasisPoints = newChangeRateBasisPoints;
    }
}