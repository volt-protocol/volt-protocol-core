// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {PegStabilityModule, Decimal, SafeERC20, SafeCast, IERC20, IPCVDeposit, Constants} from "./PegStabilityModule.sol";
import {IPriceBoundPSM} from "./IPriceBoundPSM.sol";
import {VanillaPSM} from "./VanillaPSM.sol";

/// @notice contract to create a price bound PSM
/// This contract will allow swaps when the price of the underlying token is within a certain ranges
contract VanillaPriceBoundPSM is VanillaPSM, IPriceBoundPSM {
    using Decimal for Decimal.D256;
    using SafeERC20 for IERC20;
    using SafeCast for *;

    /// @notice the default minimum acceptable oracle price floor
    uint128 public override floor;

    /// @notice the default maximum acceptable oracle price ceiling
    uint128 public override ceiling;

    /// @notice constructor
    /// @param _floor minimum acceptable oracle price
    /// @param _ceiling maximum  acceptable oracle price
    /// @param _params PSM construction params
    constructor(
        uint128 _floor,
        uint128 _ceiling,
        OracleParams memory _params,
        IERC20 _underlyingToken
    ) VanillaPSM(_params, _underlyingToken) {
        _setCeilingBasisPoints(_ceiling);
        _setFloorBasisPoints(_floor);
    }

    /// @notice sets the floor price in BP
    function setOracleFloorBasisPoints(uint128 newFloorBasisPoints)
        external
        override
        onlyGovernorOrAdmin
    {
        _setFloorBasisPoints(newFloorBasisPoints);
    }

    /// @notice sets the ceiling price in BP
    function setOracleCeilingBasisPoints(uint128 newCeilingBasisPoints)
        external
        override
        onlyGovernorOrAdmin
    {
        _setCeilingBasisPoints(newCeilingBasisPoints);
    }

    function isPriceValid() external view override returns (bool) {
        return _validPrice(readOracle());
    }

    /// @notice helper function to set the ceiling in basis points
    function _setCeilingBasisPoints(uint128 newCeilingBasisPoints) internal {
        require(
            newCeilingBasisPoints != 0,
            "PegStabilityModule: invalid ceiling"
        );
        require(
            newCeilingBasisPoints > floor,
            "PegStabilityModule: ceiling must be greater than floor"
        );
        uint128 oldCeiling = ceiling;
        ceiling = newCeilingBasisPoints;

        emit OracleCeilingUpdate(oldCeiling, ceiling);
    }

    /// @notice helper function to set the floor in basis points
    function _setFloorBasisPoints(uint128 newFloorBasisPoints) internal {
        require(newFloorBasisPoints != 0, "PegStabilityModule: invalid floor");
        require(
            newFloorBasisPoints < ceiling,
            "PegStabilityModule: floor must be less than ceiling"
        );
        uint128 oldFloor = floor;
        floor = newFloorBasisPoints;

        emit OracleFloorUpdate(oldFloor, floor);
    }

    /// @notice helper function to determine if price is within a valid range
    function _validPrice(Decimal.D256 memory price)
        internal
        view
        returns (bool valid)
    {
        valid =
            price.greaterThan(
                Decimal.ratio(floor, Constants.BASIS_POINTS_GRANULARITY)
            ) &&
            price.lessThan(
                Decimal.ratio(ceiling, Constants.BASIS_POINTS_GRANULARITY)
            );
    }

    /// @notice reverts if the price is greater than or equal to the ceiling or less than or equal to the floor
    function _validatePriceRange(Decimal.D256 memory price)
        internal
        view
        override
    {
        require(_validPrice(price), "PegStabilityModule: price out of bounds");
    }
}
