pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {MarketGovernanceOracle} from "./MarketGovernanceOracle.sol";

contract PCVOracle is CoreRefV2 {
    using SafeCast for *;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice emitted when a new illiquid venue is added
    event IlliquidVenueAdded(address illiquidVenue);

    /// @notice emitted when a new liquid venue is added
    event LiquidVenueAdded(address liquidVenue);

    /// @notice emitted when a illiquid venue is removed
    event IlliquidVenueRemoved(address illiquidVenue);

    /// @notice emitted when a liquid venue is removed
    event LiquidVenueRemoved(address liquidVenue);

    /// @notice emitted when total liquid venue PCV changes
    event LiquidVenuePCVUpdated(uint256 oldLiquidity, uint256 newLiquidity);

    /// @notice emitted when total illiquid venue PCV changes
    event IlliquidVenuePCVUpdated(uint256 oldLiquidity, uint256 newLiquidity);

    /// @notice emitted when market governance oracle is updated
    event MarketGovernanceOracleUpdated(
        address oldMgovOracle,
        address newMgovOracle
    );

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

    /// @notice scale
    uint256 public constant scale = 1e18;

    /// @param _core reference to the core smart contract
    /// @param _lastLiquidBalance last liquid balance
    /// @param _lastIlliquidBalance last illiquid balance
    constructor(
        address _core,
        uint112 _lastLiquidBalance,
        uint112 _lastIlliquidBalance
    ) CoreRefV2(_core) {
        lastLiquidBalance = _lastLiquidBalance;
        lastIlliquidBalance = _lastIlliquidBalance;
    }

    // ----------- Getters -----------

    /// @notice return all addresses listed as liquid venues
    function getLiquidVenues() public view returns (address[] memory) {
        return liquidVenues.values();
    }

    /// @notice return all addresses listed as illiquid venues
    function getIlliquidVenues() public view returns (address[] memory) {
        return illiquidVenues.values();
    }

    /// @return the ratio of liquid to illiquid assets in the Volt system
    /// using stale values and not factoring any interest or losses sustained
    /// but not realized within the system
    /// value is scaled up by 18 decimal places
    function getLiquidVenuePercentage() public view returns (uint256) {
        return
            (scale * lastLiquidBalance) /
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

    /// ------------- PCV Deposit Only API -------------

    /// @notice update the cumulative and last updated times
    /// only callable by a liquid pcv deposit
    /// this allows for lazy evaluation of the TWAPCV
    /// @param pcvDelta the amount of PCV change in the venue
    function updateLiquidBalance(int256 pcvDelta)
        external
        onlyLiquidPCVDeposit
    {
        _updateLiquidBalance(pcvDelta);
        _afterActionHook();
    }

    /// @notice update the cumulative and last updated times
    /// only callable by a liquid pcv deposit
    /// this allows for lazy evaluation of the TWAPCV
    /// @param pcvDelta the amount of PCV change in the venue
    function updateIlliquidBalance(int256 pcvDelta)
        external
        onlyIlliquidPCVDeposit
    {
        _updateIlliquidBalance(pcvDelta);
        _afterActionHook();
    }

    /// ------------- Governor Only API -------------

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
        MarketGovernanceOracle(marketGovernanceOracle).updateActualRate(
            getLiquidVenuePercentage()
        );
    }

    function _updateIlliquidBalance(int256 pcvDelta) private {
        uint256 oldLiquidity = lastIlliquidBalance;

        if (pcvDelta < 0) {
            lastIlliquidBalance -= (pcvDelta * -1).toUint256();
        } else {
            lastIlliquidBalance += pcvDelta.toUint256();
        }

        emit IlliquidVenuePCVUpdated(oldLiquidity, lastIlliquidBalance);
    }

    function _updateLiquidBalance(int256 pcvDelta) private {
        uint256 oldLiquidity = lastLiquidBalance;

        if (pcvDelta < 0) {
            lastLiquidBalance -= (pcvDelta * -1).toUint256();
        } else {
            lastLiquidBalance += pcvDelta.toUint256();
        }

        emit IlliquidVenuePCVUpdated(oldLiquidity, lastLiquidBalance);
    }

    function _addIlliquidVenue(address illiquidVenue) private {
        illiquidVenues.add(illiquidVenue);

        emit IlliquidVenueAdded(illiquidVenue);
    }

    function _addLiquidVenue(address liquidVenue) private {
        liquidVenues.add(liquidVenue);

        emit LiquidVenueAdded(liquidVenue);
    }
}
