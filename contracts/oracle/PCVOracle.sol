// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IOracleV2} from "./IOracleV2.sol";
import {IPCVOracle} from "./IPCVOracle.sol";
import {VoltRoles} from "../core/VoltRoles.sol";
import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {IPCVDepositV2} from "../pcv/IPCVDepositV2.sol";
import {DynamicVoltSystemOracle} from "./DynamicVoltSystemOracle.sol";

/// @notice Contract to centralize information about PCV in the Volt system.
/// This contract will emit events relevant for building offchain dashboards
/// of pcv growth, composition, and locations (venues).
/// This contract keeps track of the percentage of illiquid investments,
/// which allows dynamic VOLT rate based on the liquidity available for
/// redemptions (in other parts of the system).
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

    ///@notice set of whitelisted pcvDeposit addresses for withdrawal
    EnumerableSet.AddressSet private liquidVenues;

    ///@notice set of whitelisted pcvDeposit addresses for withdrawal
    EnumerableSet.AddressSet private illiquidVenues;

    /// @notice reference to the volt system oracle smart contract
    address public voltOracle;

    /// @notice last illiquid balance
    uint256 public lastIlliquidBalance;

    /// @notice last liquid balance
    uint256 public lastLiquidBalance;

    /// @notice last accumulative profits of each venue
    mapping(address => int256) public lastVenueProfits;

    /// @param _core reference to the core smart contract
    constructor(address _core) CoreRefV2(_core) {}

    // ----------- Getters -----------

    /// @notice return all addresses listed as liquid venues
    function getLiquidVenues() external view returns (address[] memory) {
        return liquidVenues.values();
    }

    /// @notice return all addresses listed as illiquid venues
    function getIlliquidVenues() external view returns (address[] memory) {
        return illiquidVenues.values();
    }

    /// @notice return all addresses that are liquid or illiquid venues
    function getAllVenues() external view returns (address[] memory) {
        uint256 liquidVenueLength = liquidVenues.length();
        uint256 illiquidVenueLength = illiquidVenues.length();
        address[] memory allVenues = new address[](
            liquidVenueLength + illiquidVenueLength
        );
        uint256 j = 0;

        /// there will never be more than 100 total venues
        /// so keep the math unchecked to save on gas
        unchecked {
            for (uint256 i = 0; i < liquidVenueLength; i++) {
                allVenues[j] = liquidVenues.at(i);
                j++;
            }

            for (uint256 i = 0; i < illiquidVenueLength; i++) {
                allVenues[j] = illiquidVenues.at(i);
                j++;
            }
        }

        return allVenues;
    }

    /// @return the ratio of liquid to illiquid assets in the Volt system
    /// using stale values and not factoring any interest or losses sustained
    /// but not realized within the system
    /// value is scaled up by 18 decimal places
    function lastLiquidVenuePercentage() public view returns (uint256) {
        uint256 _lastLiquidBalance = lastLiquidBalance;
        uint256 totalBalance = _lastLiquidBalance + lastIlliquidBalance;
        if (totalBalance == 0) return 1e18; // by convention, 100% liquid if empty
        return (1e18 * _lastLiquidBalance) / totalBalance;
    }

    /// @notice check if a venue is in the list of illiquid venues
    /// @param illiquidVenue address to check
    /// @return boolean whether or not the illiquidVenue is in the illiquid venue list
    function isIlliquidVenue(
        address illiquidVenue
    ) external view returns (bool) {
        return illiquidVenues.contains(illiquidVenue);
    }

    /// @notice check if a venue is in the list of illiquid venues
    /// @param liquidVenue address to check
    /// @return boolean whether or not the liquidVenue is in the illiquid venue list
    function isLiquidVenue(address liquidVenue) external view returns (bool) {
        return liquidVenues.contains(liquidVenue);
    }

    /// @notice check if a venue is in the list of liquid or illiquid venues
    /// @param venue address to check
    /// @return boolean whether or not the venue is part of the liquid or illiquid venue list
    function isVenue(address venue) external view returns (bool) {
        return liquidVenues.contains(venue) || illiquidVenues.contains(venue);
    }

    /// @notice get the total PCV balance by looping through the liquid and illiquid pcv deposits
    /// @dev this function is meant to be used offchain, as it is pretty gas expensive.
    function getTotalPcv()
        external
        view
        returns (uint256 liquidPcv, uint256 illiquidPcv, uint256 totalPcv)
    {
        uint256 liquidVenueLength = liquidVenues.length();
        uint256 illiquidVenueLength = illiquidVenues.length();

        /// there will never be more than 100 total venues
        /// so keep the math unchecked to save on gas
        unchecked {
            for (uint256 i = 0; i < liquidVenueLength; i++) {
                address depositAddress = liquidVenues.at(i);
                (uint256 oracleValue, bool oracleValid) = IOracleV2(
                    venueToOracle[depositAddress]
                ).read();
                require(oracleValid, "PCVOracle: invalid oracle value");

                uint256 balance = IPCVDepositV2(depositAddress).balance();
                liquidPcv += (oracleValue * balance) / 1e18;
            }

            for (uint256 i = 0; i < illiquidVenueLength; i++) {
                address depositAddress = illiquidVenues.at(i);
                (uint256 oracleValue, bool oracleValid) = IOracleV2(
                    venueToOracle[depositAddress]
                ).read();
                require(oracleValid, "PCVOracle: invalid oracle value");

                uint256 balance = IPCVDepositV2(depositAddress).balance();
                illiquidPcv += (oracleValue * balance) / 1e18;
            }

            totalPcv = liquidPcv + illiquidPcv;
        }
    }

    /// ------------- PCV Deposit Only API -------------

    /// @notice update the cumulative and last updated times
    /// only callable by a liquid pcv deposit that has previously been listed
    /// in the PCV Oracle, because an oracle has to be set for the msg.sender.
    /// this allows for lazy evaluation of the TWAPCV
    /// @param deltaBalance the amount of PCV change in the venue
    /// @param deltaProfit the amount of profit in the venue
    function updateLiquidBalance(
        int256 deltaBalance,
        int256 deltaProfit
    )
        public
        onlyVoltRole(VoltRoles.LIQUID_PCV_DEPOSIT)
        isGlobalReentrancyLocked
    {
        _updateBalance(msg.sender, deltaBalance, deltaProfit, true);
        _afterActionHook();
    }

    /// @notice update the cumulative and last updated times
    /// only callable by an illiquid pcv deposit that has previously been listed
    /// in the PCV Oracle, because an oracle has to be set for the msg.sender.
    /// this allows for lazy evaluation of the TWAPCV
    /// @param deltaProfit the amount of profit in the venue
    /// @param deltaBalance the amount of PCV change in the venue
    function updateIlliquidBalance(
        int256 deltaBalance,
        int256 deltaProfit
    )
        public
        onlyVoltRole(VoltRoles.ILLIQUID_PCV_DEPOSIT)
        isGlobalReentrancyLocked
    {
        _updateBalance(msg.sender, deltaBalance, deltaProfit, false);
        _afterActionHook();
    }

    /// ------------- Governor Only API -------------

    /// @notice set the oracle for a given venue, used to normalize
    /// balances into USD values, and correct for exceptional gains
    /// and losses that are not properly reported by the PCVDeposit
    function setVenueOracle(
        address venue,
        address newOracle
    ) external onlyGovernor {
        _setVenueOracle(venue, newOracle);
    }

    /// @notice add venues to the oracle
    /// only callable by the governor
    /// This locks system at level 1, because it needs to accrue
    /// on the added PCV Deposits (that locks at level 2).
    function addVenues(
        address[] calldata venues,
        address[] calldata oracles,
        bool[] calldata isLiquid
    ) external onlyGovernor globalLock(1) {
        uint256 length = venues.length;
        require(oracles.length == length, "PCVOracle: invalid oracles length");
        require(
            isLiquid.length == length,
            "PCVOracle: invalid isLiquid length"
        );
        bool nonZeroBalances = false;
        for (uint256 i = 0; i < length; ) {
            require(venues[i] != address(0), "PCVOracle: invalid venue");
            require(oracles[i] != address(0), "PCVOracle: invalid oracle");

            // add venue in state
            _setVenueOracle(venues[i], oracles[i]);
            _addVenue(venues[i], isLiquid[i]);

            uint256 balance = IPCVDepositV2(venues[i]).accrue();
            if (balance != 0) {
                nonZeroBalances = true;
                // no need for safe cast here because balance is always > 0
                _updateBalance(venues[i], int256(balance), 0, isLiquid[i]);
            }

            unchecked {
                ++i;
            }
        }
        if (nonZeroBalances) _afterActionHook();
    }

    /// @notice remove venues from the oracle
    /// only callable by the governor
    /// This locks system at level 1, because it needs to accrue
    /// on the added PCV Deposits (that locks at level 2).
    function removeVenues(
        address[] calldata venues,
        bool[] calldata isLiquid
    ) external onlyGovernor globalLock(1) {
        uint256 length = venues.length;
        require(
            isLiquid.length == length,
            "PCVOracle: invalid isLiquid length"
        );
        bool nonZeroBalances = false;
        for (uint256 i = 0; i < length; ) {
            require(venues[i] != address(0), "PCVOracle: invalid venue");

            uint256 balance = IPCVDepositV2(venues[i]).accrue();
            if (balance != 0) {
                nonZeroBalances = true;
                // no need for safe cast here because balance is always > 0
                _updateBalance(venues[i], -1 * int256(balance), 0, isLiquid[i]);
            }

            // remove venue from state
            _setVenueOracle(venues[i], address(0));
            _removeVenue(venues[i], isLiquid[i]);

            unchecked {
                ++i;
            }
        }
        if (nonZeroBalances) _afterActionHook();
    }

    /// @notice set the VOLT System Oracle address
    /// only callable by governor
    /// @param _voltOracle new address of the volt system oracle
    function setVoltOracle(address _voltOracle) external onlyGovernor {
        address oldVoltOracle = voltOracle;
        voltOracle = _voltOracle;

        emit VoltSystemOracleUpdated(oldVoltOracle, _voltOracle);
    }

    /// ------------- Helper Methods -------------

    function _setVenueOracle(address venue, address newOracle) private {
        // add oracle to the map(PCVDepositAddress) => OracleAddress
        address oldOracle = venueToOracle[venue];
        venueToOracle[venue] = newOracle;

        // emit event
        emit VenueOracleUpdated(venue, oldOracle, newOracle);
    }

    function _afterActionHook() private {
        if (voltOracle != address(0)) {
            DynamicVoltSystemOracle(voltOracle).updateActualRate(
                lastLiquidVenuePercentage()
            );
        }
    }

    function _updateBalance(
        address venue,
        int256 deltaBalance,
        int256 deltaProfit,
        bool isLiquid
    ) private {
        // Read oracle to get USD values of delta
        address oracle = venueToOracle[venue];
        require(oracle != address(0), "PCVOracle: invalid caller deposit");
        (uint256 oracleValue, bool oracleValid) = IOracleV2(oracle).read();
        require(oracleValid, "PCVOracle: invalid oracle value");
        // Compute USD values of delta
        int256 deltaBalanceUSD = (int256(oracleValue) * deltaBalance) / 1e18;
        int256 deltaProfitUSD = (int256(oracleValue) * deltaProfit) / 1e18;

        // SLOAD cached liquidity
        uint256 oldLiquidity = isLiquid
            ? lastLiquidBalance
            : lastIlliquidBalance;

        // Compute new liquidity value
        uint256 newLiquidity;
        if (deltaBalanceUSD < 0) {
            newLiquidity = oldLiquidity - (deltaBalanceUSD * -1).toUint256();
        } else {
            newLiquidity = oldLiquidity + deltaBalanceUSD.toUint256();
        }
        // SSTORE new liquidity's new value
        if (isLiquid) lastLiquidBalance = newLiquidity;
        else lastIlliquidBalance = newLiquidity;

        // Emit event
        emit PCVUpdated(
            msg.sender,
            isLiquid,
            block.timestamp,
            oldLiquidity,
            newLiquidity
        );

        // SLOAD accumulative profits of the venue
        int256 oldProfits = lastVenueProfits[venue];
        int256 newProfits = oldProfits + deltaProfitUSD;
        // SSTORE accumulative profits of the venue, if different,
        // and emit event.
        if (oldProfits != newProfits) {
            lastVenueProfits[venue] = newProfits;

            emit VenueProfitsUpdated(
                venue,
                isLiquid,
                block.timestamp,
                oldProfits,
                newProfits
            );
        }
    }

    function _addVenue(address venue, bool isLiquid) private {
        if (isLiquid) liquidVenues.add(venue);
        else illiquidVenues.add(venue);

        emit VenueAdded(venue, isLiquid, block.timestamp);
    }

    function _removeVenue(address venue, bool isLiquid) private {
        bool removed;
        if (isLiquid) removed = liquidVenues.remove(venue);
        else removed = illiquidVenues.remove(venue);
        require(removed, "PCVOracle: venue not found");

        emit VenueRemoved(venue, isLiquid, block.timestamp);
    }
}
