// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

interface IMarketGovernanceRewards {
    function userGaugeWeightChanged(
        address user,
        address gauge,
        uint32 cycleEnd,
        uint112 gaugeWeight,
        uint112 userWeight
    ) external;
}
