// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IOracleV2} from "./IOracleV2.sol";
import {IPCVOracle} from "./IPCVOracle.sol";
import {VoltRoles} from "../core/VoltRoles.sol";
import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {IPCVDepositV2} from "../pcv/IPCVDepositV2.sol";

/// @notice Contract to centralize information about PCV in the Volt system.
/// This contract will emit events relevant for building offchain dashboards
/// of pcv growth, composition, and locations (venues).
/// Each PCV Deposit has an oracle, which allows governance to manually
/// mark down a given PCVDeposit, if losses occur and the implementation
/// does not automatically detect it & return erroneous balance() values.
/// Oracles are also responsible for decimal normalization.
/// @author Eswak, Elliot Friedman
contract PCVOracle is IPCVOracle, CoreRefV2 {
    using SafeCast for *;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Map from venue address to oracle address. By reading an oracle
    /// value and multiplying by the PCVDeposit's balance(), the PCVOracle can
    /// know the USD value of PCV deployed in a given venue.
    mapping(address => address) public venueToOracle;

    ///@notice set of pcv deposit addresses
    EnumerableSet.AddressSet private venues;

    /// @param _core reference to the core smart contract
    constructor(address _core) CoreRefV2(_core) {}

    // ----------- Getters -----------

    /// @notice return all addresses listed as liquid venues
    function getVenues() external view returns (address[] memory) {
        return venues.values();
    }

    /// @notice check if a venue is in the list of venues
    /// @param venue address to check
    /// @return boolean whether or not the venue is in the venue list
    function isVenue(address venue) public view returns (bool) {
        return venues.contains(venue);
    }

    /// @notice get the total PCV balance by looping through the pcv deposits
    /// @dev this function is meant to be used offchain, as it is pretty gas expensive.
    function getTotalPcv() external view returns (uint256 totalPcv) {
        require(
            globalReentrancyLock().isUnlocked(),
            "PCVOracle: cannot read while entered"
        );

        uint256 venueLength = venues.length();

        /// there will never be more than 100 total venues
        /// so keep the math unchecked to save on gas
        unchecked {
            for (uint256 i = 0; i < venueLength; i++) {
                address depositAddress = venues.at(i);
                (uint256 oracleValue, bool oracleValid) = IOracleV2(
                    venueToOracle[depositAddress]
                ).read();
                require(oracleValid, "PCVOracle: invalid oracle value");

                uint256 balance = IPCVDepositV2(depositAddress).balance();
                totalPcv += (oracleValue * balance) / 1e18;
            }
        }
    }

    /// ------------- PCV Deposit Only API -------------

    /// @notice only callable by a pcv deposit that has previously been listed
    /// in the PCV Oracle, because an oracle has to be set for the msg.sender.
    /// this allows for lazy evaluation of the TWAPCV
    /// @param deltaBalance the amount of PCV change in the venue
    /// @param deltaProfit the amount of profit in the venue
    function updateBalance(
        int256 deltaBalance,
        int256 deltaProfit
    ) public onlyVoltRole(VoltRoles.PCV_DEPOSIT) isGlobalReentrancyLocked(2) {
        _readOracleAndUpdateAccounting(
            msg.sender, // venue
            deltaBalance, // deltaBalance
            deltaProfit // deltaProfit
        );
    }

    /// ------------- Governor Only API -------------

    /// @notice set the oracle for a given venue, used to normalize
    /// balances into USD values, and correct for exceptional gains
    /// and losses that are not properly reported by the PCVDeposit
    function setVenueOracle(
        address venue,
        address newOracle
    ) external onlyGovernor globalLock(1) {
        require(isVenue(venue), "PCVOracle: invalid venue");

        // Read oracles and check validity
        uint256 oldOracleValue;
        uint256 newOracleValue;

        {
            address oldOracle = venueToOracle[venue];
            bool oldOracleValid;
            bool newOracleValid;

            (oldOracleValue, oldOracleValid) = IOracleV2(oldOracle).read();
            (newOracleValue, newOracleValid) = IOracleV2(newOracle).read();
            require(oldOracleValid, "PCVOracle: invalid old oracle");
            require(newOracleValid, "PCVOracle: invalid new oracle");
        }

        // Update state
        _setVenueOracle(venue, newOracle);

        // If the venue is not empty, update accounting
        uint256 venueBalance = IPCVDepositV2(venue).accrue();
        if (venueBalance != 0) {
            // Compute balance diff
            uint256 oldBalanceUSD = (venueBalance * oldOracleValue) / 1e18;
            uint256 newBalanceUSD = (venueBalance * newOracleValue) / 1e18;
            int256 deltaBalanceUSD = int256(newBalanceUSD) -
                int256(oldBalanceUSD);

            // Update accounting (diff is reported as a profit/loss)
            _updateAccounting(venue, deltaBalanceUSD, deltaBalanceUSD);
        }
    }

    /// @notice add venues to the oracle
    /// only callable by the governor
    /// This locks system at level 1, because it needs to accrue
    /// on the added PCV Deposits (that locks at level 2).
    function addVenues(
        address[] calldata venuesToAdd,
        address[] calldata oracles
    ) external onlyGovernor globalLock(1) {
        uint256 length = venuesToAdd.length;
        require(oracles.length == length, "PCVOracle: invalid oracles length");

        for (uint256 i = 0; i < length; ) {
            require(venuesToAdd[i] != address(0), "PCVOracle: invalid venue");
            require(oracles[i] != address(0), "PCVOracle: invalid oracle");

            // add venue in state
            _setVenueOracle(venuesToAdd[i], oracles[i]);
            _addVenue(venuesToAdd[i]);

            uint256 balance = IPCVDepositV2(venuesToAdd[i]).accrue();
            if (balance != 0) {
                // no need for safe cast here because balance is always > 0
                _readOracleAndUpdateAccounting(
                    venuesToAdd[i],
                    int256(balance),
                    0
                );
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice remove venues from the oracle
    /// only callable by the governor
    /// This locks system at level 1, because it needs to accrue
    /// on the added PCV Deposits (that locks at level 2).
    function removeVenues(
        address[] calldata venuesToRemove
    ) external onlyGovernor globalLock(1) {
        uint256 length = venuesToRemove.length;
        for (uint256 i = 0; i < length; ) {
            require(
                venuesToRemove[i] != address(0),
                "PCVOracle: invalid venue"
            );

            uint256 balance = IPCVDepositV2(venuesToRemove[i]).accrue();
            if (balance != 0) {
                // no need for safe cast here because balance is always > 0
                _readOracleAndUpdateAccounting(
                    venuesToRemove[i],
                    -1 * int256(balance),
                    0
                );
            }

            // remove venue from state
            _setVenueOracle(venuesToRemove[i], address(0));
            _removeVenue(venuesToRemove[i]);

            unchecked {
                ++i;
            }
        }
    }

    /// ------------- Helper Methods -------------

    function _setVenueOracle(address venue, address newOracle) private {
        // add oracle to the map(PCVDepositAddress) => OracleAddress
        address oldOracle = venueToOracle[venue];
        venueToOracle[venue] = newOracle;

        // emit event
        emit VenueOracleUpdated(venue, oldOracle, newOracle);
    }

    function _readOracleAndUpdateAccounting(
        address venue,
        int256 deltaBalance,
        int256 deltaProfit
    ) private {
        // Read oracle to get USD values of delta
        address oracle = venueToOracle[venue];
        require(oracle != address(0), "PCVOracle: invalid caller deposit");
        (uint256 oracleValue, bool oracleValid) = IOracleV2(oracle).read();
        require(oracleValid, "PCVOracle: invalid oracle value");
        // Compute USD values of delta
        int256 deltaBalanceUSD = (int256(oracleValue) * deltaBalance) / 1e18;
        int256 deltaProfitUSD = (int256(oracleValue) * deltaProfit) / 1e18;

        _updateAccounting(venue, deltaBalanceUSD, deltaProfitUSD);
    }

    function _updateAccounting(
        address venue,
        int256 deltaBalanceUSD,
        int256 deltaProfitUSD
    ) private {
        // Emit event
        emit PCVUpdated(
            venue,
            block.timestamp,
            deltaBalanceUSD,
            deltaProfitUSD
        );

        // @dev:
        // Later, we could store accumulative balances and profits
        // for each venues here, in storage if needed by market governance.
        // For now to save on gas, we only emit events.
        // The PCVOracle can easily be swapped to a new implementation
        // by calling setPCVOracle() on Core.
    }

    function _addVenue(address venue) private {
        require(venues.add(venue), "PCVOracle: venue already listed");
        emit VenueAdded(venue, block.timestamp);
    }

    function _removeVenue(address venue) private {
        require(venues.remove(venue), "PCVOracle: venue not found");
        emit VenueRemoved(venue, block.timestamp);
    }
}
