// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Decimal} from "../external/Decimal.sol";

import {IOracle} from "./IOracle.sol";
import {VoltRoles} from "../core/VoltRoles.sol";
import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {PCVDeposit} from "../pcv/PCVDeposit.sol";
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
contract PCVOracle is CoreRefV2 {
    using Decimal for Decimal.D256;
    using SafeCast for *;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice emitted when a new venue oracle is set
    event VenueOracleUpdated(
        address indexed venue,
        address indexed oldOracle,
        address indexed newOracle
    );

    /// @notice emitted when a new venue is added
    event VenueAdded(address indexed venue, bool isIliquid, uint256 timestamp);

    /// @notice emitted when a venue is removed
    event VenueRemoved(
        address indexed venue,
        bool isIliquid,
        uint256 timestamp
    );

    /// @notice emitted when total venue PCV changes
    event PCVUpdated(
        address indexed venue,
        bool isIliquid,
        uint256 timestamp,
        uint256 oldLiquidity,
        uint256 newLiquidity
    );

    /// @notice emitted when market governance oracle is updated
    event VoltSystemOracleUpdated(address oldOracle, address newOracle);

    /// @notice Map from venue address to oracle address. By reading an oracle
    /// value and multiplying by the PCVDeposit's balance(), the PCVOracle can
    /// know the USD value of PCV deployed in a given venue.
    mapping(address => address) public venueToOracle;

    ///@notice set of whitelisted pcvDeposit addresses for withdrawal
    EnumerableSet.AddressSet private liquidVenues;

    ///@notice set of whitelisted pcvDeposit addresses for withdrawal
    EnumerableSet.AddressSet private illiquidVenues;

    /// @notice reference to the market governance oracle smart contract
    address public voltOracle;

    /// @notice last illiquid balance
    uint256 public lastIlliquidBalance;

    /// @notice last liquid balance
    uint256 public lastLiquidBalance;

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
    function getLiquidVenuePercentage() public view returns (uint256) {
        return
            (1e18 * lastLiquidBalance) /
            (lastIlliquidBalance + lastLiquidBalance);
    }

    /// @notice check if a venue is in the list of illiquid venues
    /// @param illiquidVenue address to check
    /// @return boolean whether or not the illiquidVenue is in the illiquid venue list
    function isIlliquidVenue(address illiquidVenue)
        external
        view
        returns (bool)
    {
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
        returns (
            uint256 liquidPcv,
            uint256 illiquidPcv,
            uint256 totalPcv
        )
    {
        uint256 liquidVenueLength = liquidVenues.length();
        uint256 illiquidVenueLength = illiquidVenues.length();

        /// there will never be more than 100 total venues
        /// so keep the math unchecked to save on gas
        unchecked {
            for (uint256 i = 0; i < liquidVenueLength; i++) {
                address depositAddress = liquidVenues.at(i);
                (Decimal.D256 memory oracleValue, bool oracleValid) = IOracle(
                    venueToOracle[depositAddress]
                ).read();
                require(oracleValid, "PCVO: invalid oracle value");

                liquidPcv +=
                    (oracleValue.asUint256() *
                        PCVDeposit(depositAddress).balance()) /
                    1e18;
            }

            for (uint256 i = 0; i < illiquidVenueLength; i++) {
                address depositAddress = illiquidVenues.at(i);
                (Decimal.D256 memory oracleValue, bool oracleValid) = IOracle(
                    venueToOracle[depositAddress]
                ).read();
                require(oracleValid, "PCVO: invalid oracle value");

                illiquidPcv +=
                    (oracleValue.asUint256() *
                        PCVDeposit(depositAddress).balance()) /
                    1e18;
            }

            totalPcv = liquidPcv + illiquidPcv;
        }
    }

    /// ------------- PCV Deposit Only API -------------

    /// @notice update the cumulative and last updated times
    /// only callable by a liquid pcv deposit
    /// this allows for lazy evaluation of the TWAPCV
    /// @param pcvDelta the amount of PCV change in the venue
    function updateLiquidBalance(int256 pcvDelta)
        public
        onlyVoltRole(VoltRoles.LIQUID_PCV_DEPOSIT_ROLE)
    {
        _updateBalance(_getUsdPcvDelta(msg.sender, pcvDelta), true);
        _afterActionHook();
    }

    /// @notice update the cumulative and last updated times
    /// only callable by a liquid pcv deposit
    /// this allows for lazy evaluation of the TWAPCV
    /// @param pcvDelta the amount of PCV change in the venue
    function updateIlliquidBalance(int256 pcvDelta)
        public
        onlyVoltRole(VoltRoles.ILLIQUID_PCV_DEPOSIT_ROLE)
    {
        _updateBalance(_getUsdPcvDelta(msg.sender, pcvDelta), false);
        _afterActionHook();
    }

    /// ------------- Governor Only API -------------

    /// @notice set the oracle for a given venue, used to normalize
    /// balances into USD values, and correct for exceptional gains
    /// and losses that are not properly reported by the PCVDeposit
    function setOracle(address venue, address newOracle) external onlyGovernor {
        _setOracle(venue, newOracle);
    }

    /// @notice add venues to the oracle
    /// only callable by the governor
    function addVenues(
        address[] calldata venues,
        address[] calldata oracles,
        bool[] calldata isLiquid
    ) external onlyGovernor {
        uint256 length = venues.length;
        require(oracles.length == length, "PCVO: invalid oracles length");
        require(isLiquid.length == length, "PCVO: invalid isLiquid length");
        bool nonZeroBalances = false;
        for (uint256 i = 0; i < length; ) {
            require(venues[i] != address(0), "PCVO: invalid venue");
            require(oracles[i] != address(0), "PCVO: invalid oracle");

            _setOracle(venues[i], oracles[i]);
            _addVenue(venues[i], isLiquid[i]);

            uint256 balance = PCVDeposit(venues[i]).balance();
            if (balance != 0) {
                nonZeroBalances = true;
                // no need for safe cast here because balance is always > 0
                _updateBalance(
                    _getUsdPcvDelta(venues[i], int256(balance)),
                    isLiquid[i]
                );
            }

            unchecked {
                ++i;
            }
        }
        if (nonZeroBalances) _afterActionHook();
    }

    /// @notice remove venues from the oracle
    /// only callable by the governor
    function removeVenues(address[] calldata venues, bool[] calldata isLiquid)
        external
        onlyGovernor
    {
        uint256 length = venues.length;
        require(isLiquid.length == length, "PCVO: invalid isLiquid length");
        bool nonZeroBalances = false;
        for (uint256 i = 0; i < length; ) {
            require(venues[i] != address(0), "PCVO: invalid venue");

            _setOracle(venues[i], address(0));
            _removeVenue(venues[i], isLiquid[i]);

            uint256 balance = PCVDeposit(venues[i]).balance();
            if (balance != 0) {
                nonZeroBalances = true;
                // no need for safe cast here because balance is always > 0
                _updateBalance(
                    _getUsdPcvDelta(venues[i], -1 * int256(balance)),
                    isLiquid[i]
                );
            }

            unchecked {
                ++i;
            }
        }
        if (nonZeroBalances) _afterActionHook();
    }

    /// @notice set the VOLT System Oracle address
    /// only callable by governor
    /// @param _voltOracle new address of the market governance oracle
    function setVoltOracle(address _voltOracle) external onlyGovernor {
        address oldVoltOracle = voltOracle;
        voltOracle = _voltOracle;

        emit VoltSystemOracleUpdated(oldVoltOracle, _voltOracle);
    }

    /// ------------- Helper Methods -------------

    function _setOracle(address venue, address newOracle) private {
        // add oracle to the map(PCVDepositAddress) => OracleAddress
        address oldOracle = venueToOracle[venue];
        venueToOracle[venue] = newOracle;

        // emit event
        emit VenueOracleUpdated(venue, oldOracle, newOracle);
    }

    function _getUsdPcvDelta(address venue, int256 pcvDelta)
        private
        view
        returns (int256)
    {
        address oracle = venueToOracle[venue];
        require(oracle != address(0), "PCVO: invalid caller deposit");
        (Decimal.D256 memory oracleValue, bool oracleValid) = IOracle(oracle)
            .read();
        require(oracleValid, "PCVO: invalid oracle value");
        return (int256(oracleValue.asUint256()) * pcvDelta) / 1e18;
    }

    function _afterActionHook() private {
        if (voltOracle != address(0)) {
            DynamicVoltSystemOracle(voltOracle).updateActualRate(
                getLiquidVenuePercentage()
            );
        }
    }

    function _updateBalance(int256 pcvDeltaUSD, bool isLiquid) private {
        uint256 oldLiquidity = isLiquid
            ? lastLiquidBalance
            : lastIlliquidBalance;

        uint256 newLiquidity;
        if (pcvDeltaUSD < 0) {
            newLiquidity = oldLiquidity - (pcvDeltaUSD * -1).toUint256();
        } else {
            newLiquidity = oldLiquidity + pcvDeltaUSD.toUint256();
        }

        if (isLiquid) lastLiquidBalance = newLiquidity;
        else lastIlliquidBalance = newLiquidity;

        emit PCVUpdated(
            msg.sender,
            isLiquid,
            block.timestamp,
            oldLiquidity,
            newLiquidity
        );
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
        require(removed, "PCVO: venue not found");

        emit VenueRemoved(venue, isLiquid, block.timestamp);
    }
}
