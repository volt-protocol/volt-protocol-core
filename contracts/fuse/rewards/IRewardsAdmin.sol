// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./IRewardsDistributorAdmin.sol";

interface IRewardsAdmin is IRewardsDistributorAdmin {
    function admin() external view returns (address);

    function pendingAdmin() external view returns (address);

    function claimRewards(address) external;
}
