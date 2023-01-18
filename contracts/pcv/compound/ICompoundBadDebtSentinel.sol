// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {CoreRefV2} from "../../refs/CoreRefV2.sol";
import {PCVGuardian} from "../PCVGuardian.sol";
import {IComptroller} from "./IComptroller.sol";

/// @notice Contract that removes all funds from Compound
/// when bad debt goes over a certain threshold.
/// After funds are removed from Compound, pause
/// the PCV Deposits.
/// @dev requires Guardian role.
interface ICompoundBadDebtSentinel {
    /// @notice event emitted when bad debt is detected and funds are removed from Compound PCV Deposits
    event BadDebtDetected();

    /// @notice event emitted when compound pcv deposit is added to sentinel
    event PCVDepositAdded(
        uint256 timestamp,
        address indexed caller,
        address indexed pcvDeposit
    );

    /// @notice event emitted when compound pcv deposit is removed from sentinel
    event PCVDepositRemoved(
        uint256 timestamp,
        address indexed caller,
        address indexed pcvDeposit
    );

    /// @notice event emitted when PCV Guardian is updated
    event PCVGuardianUpdated(
        address indexed oldPCVGuardian,
        address indexed newPCVGuardian
    );

    /// @notice event emitted when bad debt threshold is updated
    event BadDebtThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    /// @notice event emitted when withdraw from compound pcv deposit succeeds
    event WithdrawSucceeded(
        uint256 timestamp,
        address indexed caller,
        address indexed pcvDeposit
    );

    /// @notice event emitted when withdraw from compound pcv deposit fails
    event WithdrawFailed(
        uint256 timestamp,
        address indexed caller,
        address indexed pcvDeposit
    );

    /// ------------- Public State Changing API -------------

    /// @notice rescue funds from all stored PCV Deposits
    /// @param addresses of compound users to query for bad debt
    function rescueAllFromCompound(address[] memory addresses) external;

    /// @notice rescue assets from compound
    /// @param addresses of compound users to query for bad debt
    /// @param pcvDeposits to pull funds from
    function rescueFromCompound(
        address[] calldata addresses,
        address[] calldata pcvDeposits
    ) external;

    /// ----------- Governor Only API -----------

    /// @notice add pcv deposits to this sentinel
    /// @param newPcvDeposits to add to the sentinel
    function addPCVDeposits(address[] calldata newPcvDeposits) external;

    /// @notice remove pcv deposits from this sentinel
    /// @param pcvDeposits to remove from this sentinel
    function removePCVDeposits(address[] calldata pcvDeposits) external;

    /// @notice update the PCV Guardian
    /// @param newPCVGuardian to pull funds through
    function updatePCVGuardian(address newPCVGuardian) external;

    /// @notice update the bad debt threshold
    /// @param newBadDebtThreshold over which the sentinel can be triggered.
    function updateBadDebtThreshold(uint256 newBadDebtThreshold) external;
}
