// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Constants} from "../Constants.sol";
import {OracleRefV2} from "./../refs/OracleRefV2.sol";
import {PCVDeposit} from "./../pcv/PCVDeposit.sol";
import {IPCVDeposit} from "./../pcv/IPCVDeposit.sol";
import {IPegStabilityModule} from "./IPegStabilityModule.sol";

abstract contract BasePegStabilityModule is IPegStabilityModule, OracleRefV2 {
    using SafeERC20 for IERC20;
    using SafeCast for *;

    /// @notice the token this PSM will exchange for VOLT
    IERC20 public immutable override underlyingToken;

    /// @notice the minimum acceptable oracle price floor
    uint128 public override floor;

    /// @notice the maximum acceptable oracle price ceiling
    uint128 public override ceiling;

    /// @notice construct the PSM
    /// @param coreAddress reference to core
    /// @param oracleAddress reference to oracle
    /// @param backupOracle reference to backup oracle
    /// @param decimalsNormalizer decimal normalizer for oracle price
    /// @param doInvert invert oracle price
    /// @param underlyingTokenAddress this psm uses
    /// @param floorPrice minimum acceptable oracle price
    /// @param ceilingPrice maximum  acceptable oracle price
    constructor(
        address coreAddress,
        address oracleAddress,
        address backupOracle,
        int256 decimalsNormalizer,
        bool doInvert,
        IERC20 underlyingTokenAddress,
        uint128 floorPrice,
        uint128 ceilingPrice
    )
        OracleRefV2(
            coreAddress,
            oracleAddress,
            backupOracle,
            decimalsNormalizer,
            doInvert
        )
    {
        _setCeiling(ceilingPrice);
        _setFloor(floorPrice);
        underlyingToken = underlyingTokenAddress;
    }

    // ----------- Governor Only State Changing API -----------

    /// @notice sets the new floor price
    /// @param newFloorPrice new floor price
    function setOracleFloorPrice(
        uint128 newFloorPrice
    ) external override onlyGovernor {
        _setFloor(newFloorPrice);
    }

    /// @notice sets the new ceiling price
    /// @param newCeilingPrice new ceiling price
    function setOracleCeilingPrice(
        uint128 newCeilingPrice
    ) external override onlyGovernor {
        _setCeiling(newCeilingPrice);
    }

    /// ----------- Public View-Only API ----------

    /// @notice calculate the amount of VOLT out for a given `amountIn` of underlying
    /// First get oracle price of token
    /// Then figure out how many dollars that amount in is worth by multiplying price * amount.
    /// ensure decimals are normalized if on underlying they are not 18
    /// @param amountIn amount of underlying token in
    /// @return amountVoltOut the amount of Volt out
    /// @dev reverts if price is out of allowed range
    function getMintAmountOut(
        uint256 amountIn
    ) public view virtual returns (uint256 amountVoltOut) {
        uint256 oraclePrice = readOracle();
        _validatePriceRange(oraclePrice);

        /// This was included to make sure that precision is retained when dividing
        /// In the case where 1 USDC is deposited, which is 1e6, at the time of writing
        /// the VOLT price is $1.05 so the price we retrieve from the oracle will be 1.05e6
        /// VOLT contains 18 decimals, so when we perform the below calculation, it amounts to
        /// 1e6 * 1e18 / 1.05e6 = 1e24 / 1.05e6 which lands us at around 0.95e17, which is 0.95
        /// VOLT for 1 USDC which is consistent with the exchange rate
        /// need to multiply by 1e18 before dividing because oracle price is scaled down by
        /// -12 decimals in the case of USDC

        /// DAI example:
        /// amountIn = 1e18 (1 DAI)
        /// oraclePrice = 1.05e18 ($1.05/Volt)
        /// amountVoltOut = (amountIn * 1e18) / oraclePrice
        /// = 9.523809524E17 Volt out
        amountVoltOut = (amountIn * 1e18) / oraclePrice;
    }

    /// @notice calculate the amount of underlying out for a given `amountVoltIn` of Volt
    /// First get oracle price of token
    /// Then figure out how many dollars that amount in is worth by multiplying price * amount.
    /// ensure decimals are normalized if on underlying they are not 18
    /// @dev reverts if price is out of allowed range
    function getRedeemAmountOut(
        uint256 amountVoltIn
    ) public view override returns (uint256 amountTokenOut) {
        uint256 oraclePrice = readOracle();
        _validatePriceRange(oraclePrice);

        /// DAI Example:
        /// decimals normalizer: 0
        /// amountVoltIn = 1e18 (1 VOLT)
        /// oraclePrice = 1.05e18 ($1.05/Volt)
        /// amountTokenOut = oraclePrice * amountVoltIn / 1e18
        /// = 1.05e18 DAI out

        /// USDC Example:
        /// decimals normalizer: -12
        /// amountVoltIn = 1e18 (1 VOLT)
        /// oraclePrice = 1.05e6 ($1.05/Volt)
        /// amountTokenOut = oraclePrice * amountVoltIn / 1e18
        /// = 1.05e6 USDC out
        amountTokenOut = (oraclePrice * amountVoltIn) / 1e18;
    }

    /// @notice function from PCVDeposit that must be overriden
    function balance() public view returns (uint256) {
        return underlyingToken.balanceOf(address(this));
    }

    /// @notice returns address of token this contracts balance is reported in
    function balanceReportedIn() public view returns (address) {
        return address(underlyingToken);
    }

    /// @notice returns whether or not the current price is valid
    function isPriceValid() external view override returns (bool) {
        return _validPrice(readOracle());
    }

    /// ----------- Private Helper Functions -----------

    /// @notice helper function to set the ceiling in basis points
    function _setCeiling(uint128 newCeilingPrice) private {
        require(
            newCeilingPrice > floor,
            "PegStabilityModule: ceiling must be greater than floor"
        );
        uint128 oldCeiling = ceiling;
        ceiling = newCeilingPrice;

        emit OracleCeilingUpdate(oldCeiling, newCeilingPrice);
    }

    /// @notice helper function to set the floor in basis points
    function _setFloor(uint128 newFloorPrice) private {
        require(newFloorPrice != 0, "PegStabilityModule: invalid floor");
        require(
            newFloorPrice < ceiling,
            "PegStabilityModule: floor must be less than ceiling"
        );
        uint128 oldFloor = floor;
        floor = newFloorPrice;

        emit OracleFloorUpdate(oldFloor, newFloorPrice);
    }

    /// @notice helper function to determine if price is within a valid range
    /// @param price oracle price expressed as a decimal
    function _validPrice(uint256 price) private view returns (bool valid) {
        valid = price >= floor && price <= ceiling;
    }

    /// @notice reverts if the price is greater than or equal to the ceiling or less than or equal to the floor
    /// @param price oracle price expressed as a decimal
    function _validatePriceRange(uint256 price) private view {
        require(_validPrice(price), "PegStabilityModule: price out of bounds");
    }
}
