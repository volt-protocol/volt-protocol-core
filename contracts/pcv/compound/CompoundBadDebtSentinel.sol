// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {CoreRefV2} from "../../refs/CoreRefV2.sol";
import {PCVDeposit} from "../PCVDeposit.sol";
import {PCVGuardian} from "../PCVGuardian.sol";
import {IComptroller} from "./IComptroller.sol";
import {ICompoundBadDebtSentinel} from "./ICompoundBadDebtSentinel.sol";

/// @notice Contract that removes all funds from Compound
/// when bad debt goes over a certain threshold.
/// After funds are removed from Compound, pause
/// the PCV Deposit.
/// @dev requires the Guardian role.
contract CompoundBadDebtSentinel is ICompoundBadDebtSentinel, CoreRefV2 {
    using EnumerableSet for EnumerableSet.AddressSet;

    ///@notice set of whitelisted compound PCV Deposits
    EnumerableSet.AddressSet private compoundPcvDeposits;

    /// @notice reference to the comptroller contract
    address public immutable comptroller;

    /// @notice reference to the PCV Guardian contract
    address public pcvGuardian;

    /// @notice threshold over amount of bad debt which can trigger the sentinel
    uint256 public badDebtThreshold;

    /// @param _core reference to core
    /// @param _comptroller reference to the compound comptroller
    /// @param _pcvGuardian reference to the PCV Guardian
    /// @param _badDebtThreshold threshold over which bad debt can trigger the sentinel
    constructor(
        address _core,
        address _comptroller,
        address _pcvGuardian,
        uint256 _badDebtThreshold
    ) CoreRefV2(_core) {
        comptroller = _comptroller;
        pcvGuardian = _pcvGuardian;
        badDebtThreshold = _badDebtThreshold;
    }

    /// @notice check if an address is marked as a PCV Deposit in this contract
    /// @param pcvDeposit to check for inclusion
    /// @return whether or not the pcvDeposit can be withdrawn from with the Bad Debt Sentinel
    function isCompoundPcvDeposit(
        address pcvDeposit
    ) public view returns (bool) {
        return compoundPcvDeposits.contains(pcvDeposit);
    }

    /// @notice getter method to view all current Compound PCV Deposits
    /// @return all current Compound PCV Deposits
    function allPcvDeposits() public view returns (address[] memory) {
        return compoundPcvDeposits.values();
    }

    /// @notice returns true if the addresses are ordered from least to greatest and contain no duplicates
    /// @param addresses to check
    /// @return true if array contains no duplicates and the address are ordered
    /// returns false if the array has duplicates or is incorrectly ordered.
    function noDuplicatesAndOrdered(
        address[] memory addresses
    ) public pure returns (bool) {
        /// addresses
        unchecked {
            uint256 addressesLength = addresses.length;

            for (uint256 i = 0; i < addressesLength; i++) {
                if (i + 1 <= addressesLength - 1) {
                    if (addresses[i] >= addresses[i + 1]) {
                        return false;
                    }
                }
            }

            return true;
        }
    }

    /// @notice get the total bad debt for a given set of addresses
    /// @param addresses of users to find sum of bad debt
    /// @return totalBadDebt of all supplied users
    function getTotalBadDebt(
        address[] memory addresses
    ) public view returns (uint256 totalBadDebt) {
        uint256 accountsLength = addresses.length;

        for (uint256 i = 0; i < accountsLength; i++) {
            (, , uint256 badDebt) = IComptroller(comptroller)
                .getAccountLiquidity(addresses[i]);
            totalBadDebt += badDebt;
        }
    }

    /// ------------- Public State Changing API -------------

    /// @notice rescue funds from all stored PCV Deposits
    /// no need for the reentrancy lock as the PCV Guardian will lock when withdrawals process
    /// @param addresses of compound users to query for bad debt
    function rescueAllFromCompound(
        address[] memory addresses
    ) external override {
        _countBadDebtAndWithdraw(addresses, allPcvDeposits());
    }

    /// @notice rescue assets from compound, then pause all deposits
    /// no need for the reentrancy lock as the PCV Guardian will lock when withdrawals process
    /// @param addresses of compound users to query for bad debt
    /// @param pcvDeposits to pull funds from
    function rescueFromCompound(
        address[] memory addresses,
        address[] memory pcvDeposits
    ) external override {
        uint256 pcvDepositsLength = pcvDeposits.length;

        /// validate pcv deposits are ordered and not duplicated
        require(
            noDuplicatesAndOrdered(pcvDeposits),
            "CompoundBadDebtSentinel: PCVDeposits, Duplicates or OOO"
        );

        /// validate pcv deposits are in whitelist
        unchecked {
            for (uint256 i = 0; i < pcvDepositsLength; i++) {
                require(
                    isCompoundPcvDeposit(pcvDeposits[i]),
                    "CompoundBadDebtSentinel: Invalid Compound PCV Deposit"
                );
            }
        }

        _countBadDebtAndWithdraw(addresses, pcvDeposits);
    }

    /// @notice helper method that validates no duplicate user addresses are passed in
    /// @param addresses of compound users to query for bad debt
    /// @param pcvDeposits to pull funds from
    function _countBadDebtAndWithdraw(
        address[] memory addresses,
        address[] memory pcvDeposits
    ) private {
        require(
            noDuplicatesAndOrdered(addresses),
            "CompoundBadDebtSentinel: Addresses, Duplicates or OOO"
        );

        uint256 pcvDepositsLength = pcvDeposits.length;

        /// figure out how much bad debt exists
        /// at this point, we know there are no duplicate accounts in the address array
        uint256 totalBadDebt = getTotalBadDebt(addresses);

        if (totalBadDebt >= badDebtThreshold) {
            unchecked {
                for (uint256 i = 0; i < pcvDepositsLength; i++) {
                    /// morpho reverts on withdrawing 0 balance
                    /// so do not withdraw on 0 balance
                    if (PCVDeposit(pcvDeposits[i]).balance() != 0) {
                        try
                            PCVGuardian(pcvGuardian).withdrawAllToSafeAddress(
                                pcvDeposits[i]
                            )
                        {
                            emit WithdrawSucceeded(
                                block.timestamp,
                                msg.sender,
                                pcvDeposits[i]
                            );
                        } catch {
                            emit WithdrawFailed(
                                block.timestamp,
                                msg.sender,
                                pcvDeposits[i]
                            );
                        }
                    }

                    PCVDeposit(pcvDeposits[i]).pause();
                }
            }

            emit BadDebtDetected();
        }
    }

    /// ----------- Governor Only API -----------

    /// @notice add pcv deposits to this sentinel
    /// @param newPcvDeposits to add to the sentinel
    function addPCVDeposits(
        address[] calldata newPcvDeposits
    ) external override onlyGovernor {
        uint256 pcvDepositsLength = newPcvDeposits.length;

        unchecked {
            for (uint256 i = 0; i < pcvDepositsLength; i++) {
                compoundPcvDeposits.add(newPcvDeposits[i]);
                emit PCVDepositAdded(
                    block.timestamp,
                    msg.sender,
                    newPcvDeposits[i]
                );
            }
        }
    }

    /// @notice remove pcv deposits from this sentinel
    /// @param pcvDeposits to remove from this sentinel
    function removePCVDeposits(
        address[] calldata pcvDeposits
    ) external override onlyGovernor {
        uint256 pcvDepositsLength = pcvDeposits.length;

        unchecked {
            for (uint256 i = 0; i < pcvDepositsLength; i++) {
                require(
                    compoundPcvDeposits.remove(pcvDeposits[i]),
                    "CompoundBadDebtSentinel: deposit not found"
                );
                emit PCVDepositRemoved(
                    block.timestamp,
                    msg.sender,
                    pcvDeposits[i]
                );
            }
        }
    }

    /// @notice update the PCV Guardian
    /// @param newPCVGuardian to pull funds through
    function updatePCVGuardian(
        address newPCVGuardian
    ) external override onlyGovernor {
        address oldPCVGuardian = pcvGuardian;

        pcvGuardian = newPCVGuardian;

        emit PCVGuardianUpdated(oldPCVGuardian, newPCVGuardian);
    }

    /// @notice update the bad debt threshold
    /// @param newBadDebtThreshold over which the sentinel can be triggered.
    function updateBadDebtThreshold(
        uint256 newBadDebtThreshold
    ) external override onlyGovernor {
        uint256 oldBadDebtThreshold = badDebtThreshold;

        badDebtThreshold = newBadDebtThreshold;

        emit BadDebtThresholdUpdated(oldBadDebtThreshold, newBadDebtThreshold);
    }
}
