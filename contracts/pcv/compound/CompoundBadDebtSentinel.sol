// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {CoreRefV2} from "../../refs/CoreRefV2.sol";
import {PCVGuardian} from "../PCVGuardian.sol";
import {IComptroller} from "./IComptroller.sol";
import {ERC20Allocator} from "../utils/ERC20Allocator.sol";

/// @notice Contract that removes all funds from Compound
/// when bad debt goes over a certain threshold.
/// After funds are removed from Compound, disconnect
/// the PCV Deposits from the ERC20 Allocator.
/// @dev requires PCV Guardian role and the PCV SENTINEL role.
contract CompoundBadDebtSentinel is CoreRefV2 {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice event emitted when bad debt is detected and funds are removed from Compound PCV Deposits
    event BadDebtDetected(
        uint256 timestamp,
        address indexed caller,
        address[] pcvDeposits
    );

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

    /// @notice event emitted when ERC20 Allocator is updated
    event ERC20AllocatorUpdated(
        address indexed oldAllocator,
        address indexed newAllocator
    );

    /// @notice event emitted when ERC20 Allocator is updated
    event BadDebtThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    ///@notice set of whitelisted compound PCV Deposits
    EnumerableSet.AddressSet private compoundPcvDeposits;

    /// @notice reference to the comptroller contract
    address public immutable comptroller;

    /// @notice reference to the PCV Guardian contract
    address public pcvGuardian;

    /// @notice reference to the ERC20 Allocator contract
    address public erc20Allocator;

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
        address _erc20Allocator,
        uint256 _badDebtThreshold
    ) CoreRefV2(_core) {
        comptroller = _comptroller;
        pcvGuardian = _pcvGuardian;
        erc20Allocator = _erc20Allocator;
        badDebtThreshold = _badDebtThreshold;
    }

    /// @notice returns true if the addresses are ordered and contain no duplicates
    /// @param addresses to check
    /// @return true if no duplicates and the address are ordered
    function noDuplicatesAndOrdered(
        address[] calldata addresses
    ) private pure returns (bool) {
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

    /// ------------- Public State Changing API -------------

    /// @notice rescue assets from compound
    /// @param addresses of compound users to query for bad debt
    /// @param pcvDeposits to pull funds from
    function rescueFromCompound(
        address[] calldata addresses,
        address[] calldata pcvDeposits
    ) external {
        uint256 pcvDepositsLength = pcvDeposits.length;
        uint256 accountsLength = addresses.length;

        require(
            noDuplicatesAndOrdered(addresses),
            "CompoundBadDebtSentinel: Addresses, Duplicates or OOO"
        );
        require(
            noDuplicatesAndOrdered(pcvDeposits),
            "CompoundBadDebtSentinel: PCVDeposits, Duplicates or OOO"
        );

        /// validate pcv deposits
        unchecked {
            for (uint256 i = 0; i < pcvDepositsLength; i++) {
                require(
                    compoundPcvDeposits.contains(pcvDeposits[i]),
                    "CompoundBadDebtSentinel: Invalid Compound PCV Deposit"
                );
            }
        }

        /// figure out how much bad debt exists
        /// need filter duplicates out of accounts and pcvDeposits
        uint256 totalBadDebt = 0;
        for (uint256 i = 0; i < accountsLength; i++) {
            (, , uint256 badDebt) = IComptroller(comptroller)
                .getAccountLiquidity(addresses[i]);
            totalBadDebt += badDebt;
        }

        if (totalBadDebt >= badDebtThreshold) {
            unchecked {
                for (uint256 i = 0; i < pcvDepositsLength; i++) {
                    PCVGuardian(pcvGuardian).withdrawAllToSafeAddress(
                        pcvDeposits[i]
                    );
                    ERC20Allocator(erc20Allocator).deleteDeposit(
                        pcvDeposits[i]
                    );
                }
            }

            emit BadDebtDetected(block.timestamp, msg.sender, addresses);
        }
    }

    /// ----------- Governor Only API -----------

    /// @notice add pcv deposits to this sentinel
    /// @param newPcvDeposits to add to the sentinel
    function addPCVDeposits(
        address[] calldata newPcvDeposits
    ) external onlyGovernor {
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
    ) external onlyGovernor {
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
    function updatePCVGuardian(address newPCVGuardian) external onlyGovernor {
        address oldPCVGuardian = pcvGuardian;

        pcvGuardian = newPCVGuardian;

        emit PCVGuardianUpdated(oldPCVGuardian, newPCVGuardian);
    }

    /// @notice update the ERC20 Allocator
    /// @param newAllocator to point to
    function updateERC20Allocator(address newAllocator) external onlyGovernor {
        address oldAllocator = erc20Allocator;

        erc20Allocator = newAllocator;

        emit ERC20AllocatorUpdated(oldAllocator, newAllocator);
    }

    /// @notice update the bad debt threshold
    /// @param newBadDebtThreshold over which the sentinel can be triggered.
    function updateBadDebtThreshold(
        uint256 newBadDebtThreshold
    ) external onlyGovernor {
        uint256 oldBadDebtThreshold = badDebtThreshold;

        badDebtThreshold = newBadDebtThreshold;

        emit BadDebtThresholdUpdated(oldBadDebtThreshold, newBadDebtThreshold);
    }
}
