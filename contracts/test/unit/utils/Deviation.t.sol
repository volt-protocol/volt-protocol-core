// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Vm} from "@forge-std/Vm.sol";
import {Test} from "@forge-std/Test.sol";
import {Constants} from "./../../../Constants.sol";
import {Deviation} from "./../../../utils/Deviation.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract UnitTestDeviation is Test {
    using SafeCast for *;
    using Deviation for *;

    uint256 maxDeviationThresholdBasisPoints = 10_000;

    function testDeviation() public {
        int256 x = 275000;
        int256 y = 270000;

        int256 delta = x - y;
        uint256 absDeviation = delta.toUint256();

        uint256 basisPoints = (absDeviation *
            Constants.BASIS_POINTS_GRANULARITY) / x.toUint256();

        assertEq(
            basisPoints,
            Deviation.calculateDeviationThresholdBasisPoints(x, y)
        );
    }

    function testDeviationPpq() public {
        int256 x = 1 ether + 1;
        int256 y = 1 ether;

        int256 delta = x - y;
        uint256 absDeviation = delta.toUint256();

        uint256 ppqDeviation = (absDeviation * 1e18) / x.toUint256();

        assertEq(ppqDeviation, Deviation.calculateDeviationThresholdPPQ(x, y));
    }

    function testWithinDeviation() public {
        int256 x = 275000;
        int256 y = 270000;

        assertTrue(
            maxDeviationThresholdBasisPoints.isWithinDeviationThreshold(x, y)
        );
    }

    function testOutsideDeviation() public {
        int256 x = 275000;
        int256 y = 577500;

        assertTrue(
            !maxDeviationThresholdBasisPoints.isWithinDeviationThreshold(x, y)
        );
    }
}
