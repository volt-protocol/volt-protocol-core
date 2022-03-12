// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {IScalingPriceOracle} from "./../oracle/IScalingPriceOracle.sol";

contract MockChainlinkSingleUpdateOracle {
    IScalingPriceOracle public scalingPriceOracle;

    constructor(IScalingPriceOracle _scalingPriceOracle) {
        scalingPriceOracle = _scalingPriceOracle;
    }

    function updateOracleAPRBasisPoints(int256 newChangeRateBasisPoints)
        external
    {
        scalingPriceOracle.oracleUpdateChangeRate(newChangeRateBasisPoints);
    }
}
