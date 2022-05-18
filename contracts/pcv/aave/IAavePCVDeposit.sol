// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IERC20, CoreRef} from "./../PCVDeposit.sol";

interface LendingPool {
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external;
}

interface IncentivesController {
    function claimRewards(
        address[] calldata assets,
        uint256 amount,
        address to
    ) external;

    function getRewardsBalance(address[] calldata assets, address user)
        external
        view
        returns (uint256);
}

/// @title Aave PCV Deposit
/// @author Volt Protocol
interface IAavePCVDeposit {
    /// @notice event emitted when rewards are claimed
    event ClaimRewards(address indexed caller, uint256 amount);

    /// @notice the associated Aave aToken for the deposit
    function aToken() external view returns (IERC20);

    /// @notice the Aave v2 lending pool
    function lendingPool() external view returns (LendingPool);

    /// @notice the underlying token of the PCV deposit
    function token() external view returns (IERC20);

    /// @notice the Aave incentives controller for the aToken
    function incentivesController()
        external
        view
        returns (IncentivesController);

    /// @notice claims Aave rewards from the deposit and transfers to this address
    function claimRewards() external;
}
