pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {CoreRefV2} from "../refs/CoreRefV2.sol";

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

    ///@notice set of whitelisted pcvDeposit addresses for withdrawal
    EnumerableSet.AddressSet private liquidVenues;

    ///@notice set of whitelisted pcvDeposit addresses for withdrawal
    EnumerableSet.AddressSet private illiquidVenues;

    uint256 public lastIlliquidBalance;

    uint256 public lastLiquidBalance;

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

    function getLiquidVenues() public view returns (address[] memory) {
        return liquidVenues.values();
    }

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

    /// @notice update the cumulative and last updated times
    /// only callable by a liquid pcv deposit
    /// this allows for lazy evaluation of the TWAPCV
    /// @param pcvDelta the amount of PCV change in the venue
    function updateLiquidBalance(int256 pcvDelta)
        external
        onlyLiquidPCVDeposit
    {
        _updateLiquidBalance(pcvDelta);
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
    }

    //// HELPERS
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

    /// @notice add illiquid venues to the oracle
    /// only callable by the governor
    /// 1. record starting illiquid balance by calling updateIlliquidBalance with 0 delta
    /// 2. add venues
    /// 3. governance action or later should call deposit
    /// (implicit) disallow deposit being called if contract does not have PCV deposit role
    function addIlliquidVenues(address[] calldata illiquidVenuesToAdd)
        external
        onlyGovernor
    {
        _updateIlliquidBalance(0);

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
    /// 1. record starting liquid balance by calling updateLiquidBalance with 0 delta
    /// 2. add venues
    /// 3. governance action or later should call deposit
    /// (implicit) disallow deposit being called if contract does not have PCV deposit role
    function addLiquidVenues(address[] calldata liquidVenuesToAdd)
        external
        onlyGovernor
    {
        _updateLiquidBalance(0);

        uint256 liquidVenueLength = liquidVenuesToAdd.length;
        for (uint256 i = 0; i < liquidVenueLength; ) {
            _addLiquidVenue(liquidVenuesToAdd[i]);
            unchecked {
                ++i;
            }
        }
    }

    function isIlliquidVenue(address illiquidVenue) public view returns (bool) {
        return illiquidVenues.contains(illiquidVenue);
    }

    function isLiquidVenue(address liquidVenue) public view returns (bool) {
        return liquidVenues.contains(liquidVenue);
    }

    /**
     * @dev Returns the downcasted uint112 from uint256, reverting on
     * overflow (when the input is greater than largest uint112).
     *
     * Counterpart to Solidity's `uint112` operator.
     *
     * Requirements:
     *
     * - input must fit into 112 bits
     */
    function toUint112(uint256 value) internal pure returns (uint112) {
        require(
            value <= type(uint112).max,
            "SafeCast: value doesn't fit in 112 bits"
        );
        return uint112(value);
    }
}
