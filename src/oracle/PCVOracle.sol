// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {Constants} from "@voltprotocol/Constants.sol";
import {IOracleV2} from "@voltprotocol/oracle/IOracleV2.sol";
import {IPCVOracle} from "@voltprotocol/oracle/IPCVOracle.sol";
import {VoltRoles} from "@voltprotocol/core/VoltRoles.sol";
import {CoreRefV2} from "@voltprotocol/refs/CoreRefV2.sol";
import {IPCVDepositV2} from "@voltprotocol/pcv/IPCVDepositV2.sol";

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

    /// @notice track the venue's profit and losses
    struct VenueData {
        /// @notice  last recorded balance of PCV Deposit
        int128 lastRecordedBalance;
        /// @notice last recorded profit of PCV Deposit
        int128 lastRecordedProfit;
    }

    /// @notice venue information, balance and profit
    mapping(address => VenueData) public venueRecord;

    /// @notice cached total PCV amount
    uint256 public totalRecordedPcv;

    ///@notice set of pcv deposit addresses
    EnumerableSet.AddressSet private venues;

    /// @param _core reference to the core smart contract
    constructor(address _core) CoreRefV2(_core) {}

    // ----------- Getters -----------

    /// @notice return all addresses listed as liquid venues
    function getVenues() external view returns (address[] memory) {
        return venues.values();
    }

    /// @notice return all addresses listed as liquid venues
    function getNumVenues() external view returns (uint256) {
        return venues.length();
    }

    /// @notice check if a venue is in the list of venues
    /// @param venue address to check
    /// @return boolean whether or not the venue is in the venue list
    function isVenue(address venue) public view returns (bool) {
        return venues.contains(venue);
    }

    /// @notice return last recorded balance for venue
    function lastRecordedBalance(address venue) public view returns (int128) {
        return venueRecord[venue].lastRecordedBalance;
    }

    /// @notice return last recorded profit for venue
    function lastRecordedProfit(address venue) public view returns (int128) {
        return venueRecord[venue].lastRecordedProfit;
    }

    /// @notice get the total PCV balance by looping through the pcv deposits
    /// @dev this function is meant to be used offchain, as it is pretty gas expensive.
    /// this is an unsafe operation as it does not enforce the system is in an unlocked state
    function getTotalPcv() external view returns (uint256 totalPcv) {
        uint256 venueLength = venues.length();

        for (uint256 i = 0; i < venueLength; ) {
            address depositAddress = venues.at(i);
            (uint256 oracleValue, bool oracleValid) = IOracleV2(
                venueToOracle[depositAddress]
            ).read();
            require(oracleValid, "PCVOracle: invalid oracle value");

            uint256 balance = IPCVDepositV2(depositAddress).balance();
            totalPcv += (oracleValue * balance) / Constants.ETH_GRANULARITY;
            /// there will never be more than 100 total venues
            /// keep iteration math unchecked to save on gas
            unchecked {
                i++;
            }
        }
    }

    /// @notice get the total PCV balance by looping through the pcv deposits
    /// @dev this function is meant to be used offchain, as it is pretty gas expensive.
    /// this is an unsafe operation as it does not enforce the system is in an unlocked state
    function getTotalCachedPcv() external view returns (uint256 totalPcv) {
        uint256 venueLength = venues.length();

        for (uint256 i = 0; i < venueLength; ) {
            address depositAddress = venues.at(i);
            totalPcv += getVenueStaleBalance(depositAddress);

            /// there will never be more than 100 total venues
            /// keep iteration math unchecked to save on gas
            unchecked {
                i++;
            }
        }
    }

    /// @notice returns decimal normalized version of a given venues USD balance
    function getVenueBalance(
        address venue
    ) external view override returns (uint256) {
        // Read oracle to get USD values of delta
        address oracle = venueToOracle[venue];

        require(oracle != address(0), "PCVOracle: invalid caller deposit");
        (uint256 oracleValue, bool oracleValid) = IOracleV2(oracle).read();

        require(oracleValid, "PCVOracle: invalid oracle value");
        uint256 venueBalance = IPCVDepositV2(venue).balance();

        // Compute USD values of deposit
        return (oracleValue * venueBalance) / Constants.ETH_GRANULARITY;
    }

    /// @notice returns decimal normalized version of a given venues stale USD balance
    /// does not account for unearned yield
    function getVenueStaleBalance(address venue) public view returns (uint256) {
        // Read oracle to get USD values of delta
        address oracle = venueToOracle[venue];

        require(oracle != address(0), "PCVOracle: invalid caller deposit");
        (uint256 oracleValue, bool oracleValid) = IOracleV2(oracle).read();

        require(oracleValid, "PCVOracle: invalid oracle value");

        uint256 venueBalance = venueRecord[venue]
            .lastRecordedBalance
            .toUint256();

        // Compute USD values of deposit
        return (oracleValue * venueBalance) / Constants.ETH_GRANULARITY;
    }

    /// @notice returns decimal normalized version of a given venues USD pnl
    function getVenueStaleProfit(
        address venue
    ) external view returns (uint256) {
        // Read oracle to get USD values of delta
        address oracle = venueToOracle[venue];

        require(oracle != address(0), "PCVOracle: invalid caller deposit");
        (uint256 oracleValue, bool oracleValid) = IOracleV2(oracle).read();

        require(oracleValid, "PCVOracle: invalid oracle value");

        uint256 venueProfit = venueRecord[venue].lastRecordedProfit.toUint256();

        // Compute USD values of profit
        return (oracleValue * venueProfit) / Constants.ETH_GRANULARITY;
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
            uint256 oldBalanceUSD = (venueBalance * oldOracleValue) /
                Constants.ETH_GRANULARITY;
            uint256 newBalanceUSD = (venueBalance * newOracleValue) /
                Constants.ETH_GRANULARITY;
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
                // no need for safe cast here because balance is always > 0 and < int256 max
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
        int256 deltaBalanceUSD = (int256(oracleValue) * deltaBalance) /
            Constants.ETH_GRANULARITY_INT;
        int256 deltaProfitUSD = (int256(oracleValue) * deltaProfit) /
            Constants.ETH_GRANULARITY_INT;

        _updateAccounting(venue, deltaBalanceUSD, deltaProfitUSD);
    }

    function _updateAccounting(
        address venue,
        int256 deltaBalanceUSD,
        int256 deltaProfitUSD
    ) private {
        VenueData storage ptr = venueRecord[venue];

        int128 newLastRecordedBalance = ptr.lastRecordedBalance +
            deltaBalanceUSD.toInt128();
        int128 newLastRecordedProfit = ptr.lastRecordedProfit +
            deltaProfitUSD.toInt128();

        /// single SSTORE
        ptr.lastRecordedBalance = newLastRecordedBalance;
        ptr.lastRecordedProfit = newLastRecordedProfit;

        /// update totalRecordedPcv
        if (deltaBalanceUSD < 0) {
            /// turn negative value positive, then subtract from uint256
            totalRecordedPcv =
                totalRecordedPcv -
                (-deltaBalanceUSD).toUint256();
        } else {
            /// if >= 0, safecast will never revert
            totalRecordedPcv += deltaBalanceUSD.toUint256();
        }

        // Emit event
        emit PCVUpdated(
            venue,
            block.timestamp,
            deltaBalanceUSD,
            deltaProfitUSD
        );
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
