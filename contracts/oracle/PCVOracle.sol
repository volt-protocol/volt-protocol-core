pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Decimal} from "../external/Decimal.sol";

import {IOracle} from "./IOracle.sol";
import {VoltRoles} from "../core/VoltRoles.sol";
import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {PCVDeposit} from "../pcv/PCVDeposit.sol";
import {MarketGovernanceOracle} from "./MarketGovernanceOracle.sol";

contract PCVOracle is CoreRefV2 {
    using Decimal for Decimal.D256;
    using SafeCast for *;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice emitted when a new token oracle is set
    event OracleUpdate(
        address indexed token,
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
    event MarketGovernanceOracleUpdated(
        address oldMgovOracle,
        address newMgovOracle
    );

    /// @notice Map of oracles to use to get USD values of assets held in
    ///         PCV deposits. This map is used to get the oracle address from
    ///         and ERC20 address.
    mapping(address => address) public tokenToOracle;

    /// @notice Map from deposit address to token address. It is used the oracle
    /// of a PCVDeposit by using tokenToOracle(depositToToken(depositAddress)).
    mapping(address => address) public depositToToken;

    ///@notice set of whitelisted pcvDeposit addresses for withdrawal
    EnumerableSet.AddressSet private liquidVenues;

    ///@notice set of whitelisted pcvDeposit addresses for withdrawal
    EnumerableSet.AddressSet private illiquidVenues;

    /// @notice reference to the market governance oracle smart contract
    address public marketGovernanceOracle;

    /// @notice last illiquid balance
    uint256 public lastIlliquidBalance;

    /// @notice last liquid balance
    uint256 public lastLiquidBalance;

    /// @notice scale for percentage of liquid reserves
    uint256 public constant SCALE = 1e18;

    /// @param _core reference to the core smart contract
    constructor(address _core) CoreRefV2(_core) {}

    // ----------- Getters -----------

    /// @notice return all addresses listed as liquid venues
    function getLiquidVenues() public view returns (address[] memory) {
        return liquidVenues.values();
    }

    /// @notice return all addresses listed as illiquid venues
    function getIlliquidVenues() public view returns (address[] memory) {
        return illiquidVenues.values();
    }

    /// @notice return all addresses that are liquid or illiquid venues
    function getAllVenues() public view returns (address[] memory) {
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
            (SCALE * lastLiquidBalance) /
            (lastIlliquidBalance + lastLiquidBalance);
    }

    /// @notice check if a venue is in the list of illiquid venues
    /// @param illiquidVenue address to check
    /// @return boolean whether or not the illiquidVenue is in the illiquid venue list
    function isIlliquidVenue(address illiquidVenue) public view returns (bool) {
        return illiquidVenues.contains(illiquidVenue);
    }

    /// @notice check if a venue is in the list of illiquid venues
    /// @param liquidVenue address to check
    /// @return boolean whether or not the liquidVenue is in the illiquid venue list
    function isLiquidVenue(address liquidVenue) public view returns (bool) {
        return liquidVenues.contains(liquidVenue);
    }

    /// @notice check if a venue is in the list of liquid or illiquid venues
    /// @param venue address to check
    /// @return boolean whether or not the venue is part of the liquid or illiquid venue list
    function isVenue(address venue) public view returns (bool) {
        return liquidVenues.contains(venue) || illiquidVenues.contains(venue);
    }

    /// @notice get the total PCV balance by looping through the liquid and illiquid pcv deposits
    /// @dev this function is meant to be used offchain, as it is pretty gas expensive. It also reads
    /// the fresh balance and not the resistant balance of PCVDeposits, which could be subject to
    /// in-block manipulations.
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
                    tokenToOracle[depositToToken[depositAddress]]
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
                    tokenToOracle[depositToToken[depositAddress]]
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
        external
        onlyVoltRole(VoltRoles.LIQUID_PCV_DEPOSIT_ROLE)
    {
        address token = PCVDeposit(msg.sender).balanceReportedIn();
        IOracle oracle = IOracle(tokenToOracle[token]);
        (Decimal.D256 memory oracleValue, bool oracleValid) = oracle.read();
        require(oracleValid, "PCVO: invalid oracle value");
        int256 usdPcvDelta = (int256(oracleValue.asUint256()) * pcvDelta) /
            1e18;

        _updateLiquidBalance(usdPcvDelta);
        _afterActionHook();
    }

    /// @notice update the cumulative and last updated times
    /// only callable by a liquid pcv deposit
    /// this allows for lazy evaluation of the TWAPCV
    /// @param pcvDelta the amount of PCV change in the venue
    function updateIlliquidBalance(int256 pcvDelta)
        external
        onlyVoltRole(VoltRoles.ILLIQUID_PCV_DEPOSIT_ROLE)
    {
        address token = PCVDeposit(msg.sender).balanceReportedIn();
        IOracle oracle = IOracle(tokenToOracle[token]);
        (Decimal.D256 memory oracleValue, bool oracleValid) = oracle.read();
        require(oracleValid, "PCVO: invalid oracle value");
        int256 usdPcvDelta = (int256(oracleValue.asUint256()) * pcvDelta) /
            1e18;

        _updateIlliquidBalance(usdPcvDelta);
        _afterActionHook();
    }

    /// ------------- Governor Only API -------------

    /// @notice set the oracle for a given token, used to normalize
    /// balances into USD values.
    function setOracle(address token, address newOracle) external onlyGovernor {
        // add oracle to the map(ERC20Address) => OracleAddress
        address oldOracle = tokenToOracle[token];
        tokenToOracle[token] = newOracle;

        // emit event
        emit OracleUpdate(token, oldOracle, newOracle);
    }

    /// @notice add illiquid venues to the oracle
    /// only callable by the governor
    /// 1. add venues
    /// 2. governance action or later should call deposit thus benchmarking the previous balance
    /// (implicit) disallow deposit being called if contract does not have PCV deposit role
    function addIlliquidVenues(address[] calldata illiquidVenuesToAdd)
        external
        onlyGovernor
    {
        uint256 illiquidVenueLength = illiquidVenuesToAdd.length;
        for (uint256 i = 0; i < illiquidVenueLength; ) {
            _addIlliquidVenue(illiquidVenuesToAdd[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice add liquid venues to the oracle
    /// only callable by the governor
    /// 1. add venues
    /// 2. governance action or later should call deposit, thus benchmarking the previous balance
    /// (implicit) disallow deposit being called if contract does not have PCV deposit role
    function addLiquidVenues(address[] calldata liquidVenuesToAdd)
        external
        onlyGovernor
    {
        uint256 liquidVenueLength = liquidVenuesToAdd.length;
        for (uint256 i = 0; i < liquidVenueLength; ) {
            _addLiquidVenue(liquidVenuesToAdd[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice set the market governance oracle address
    /// only callable by governor
    /// @param _marketGovernanceOracle new address of the market governance oracle
    function setMarketGovernanceOracle(address _marketGovernanceOracle)
        external
        onlyGovernor
    {
        address oldMarketGovernanceOracle = marketGovernanceOracle;
        marketGovernanceOracle = _marketGovernanceOracle;

        emit MarketGovernanceOracleUpdated(
            oldMarketGovernanceOracle,
            _marketGovernanceOracle
        );
    }

    /// ------------- Helper Methods -------------

    function _afterActionHook() private {
        if (marketGovernanceOracle != address(0)) {
            MarketGovernanceOracle(marketGovernanceOracle).updateActualRate(
                getLiquidVenuePercentage()
            );
        }
    }

    function _updateIlliquidBalance(int256 pcvDelta) private {
        uint256 oldLiquidity = lastIlliquidBalance;

        if (pcvDelta < 0) {
            lastIlliquidBalance -= (pcvDelta * -1).toUint256();
        } else {
            lastIlliquidBalance += pcvDelta.toUint256();
        }

        emit PCVUpdated(
            msg.sender,
            true,
            block.timestamp,
            oldLiquidity,
            lastIlliquidBalance
        );
    }

    function _updateLiquidBalance(int256 pcvDelta) private {
        uint256 oldLiquidity = lastLiquidBalance;

        if (pcvDelta < 0) {
            lastLiquidBalance -= (pcvDelta * -1).toUint256();
        } else {
            lastLiquidBalance += pcvDelta.toUint256();
        }

        emit PCVUpdated(
            msg.sender,
            false,
            block.timestamp,
            oldLiquidity,
            lastLiquidBalance
        );
    }

    function _addIlliquidVenue(address illiquidVenue) private {
        address token = PCVDeposit(illiquidVenue).balanceReportedIn();
        address oracle = tokenToOracle[token];
        require(oracle != address(0), "PCVO: No oracle configured");

        illiquidVenues.add(illiquidVenue);
        depositToToken[illiquidVenue] = token;

        emit VenueAdded(illiquidVenue, true, block.timestamp);
    }

    function _addLiquidVenue(address liquidVenue) private {
        address token = PCVDeposit(liquidVenue).balanceReportedIn();
        address oracle = tokenToOracle[token];
        require(oracle != address(0), "PCVO: No oracle configured");

        liquidVenues.add(liquidVenue);
        depositToToken[liquidVenue] = token;

        emit VenueAdded(liquidVenue, false, block.timestamp);
    }
}
