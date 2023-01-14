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

contract PegStabilityModule is IPegStabilityModule, OracleRefV2 {
    using SafeERC20 for IERC20;
    using SafeCast for *;

    /// @notice the token this PSM will exchange for VOLT
    /// This token will be set to WETH9 if the bonding curve accepts eth
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

    // ----------- PCV Controller Only State Changing API -----------

    /// @notice withdraw assets from PSM to an external address
    /// @param to recipient
    /// @param amount of tokens to withdraw
    function withdraw(
        address to,
        uint256 amount
    ) external onlyPCVController globalLock(2) {
        underlyingToken.safeTransfer(to, amount);
        emit Withdrawal(msg.sender, to, amount);
    }

    /// @notice withdraw ERC20 from the contract
    /// @param token address of the ERC20 to send
    /// @param to address destination of the ERC20
    /// @param amount quantity of ERC20 to send
    function withdrawERC20(
        address token,
        address to,
        uint256 amount
    ) external onlyPCVController {
        IERC20(token).safeTransfer(to, amount);
        emit WithdrawERC20(msg.sender, token, to, amount);
    }

    // ----------- Public State Changing API -----------

    /// @notice function to redeem VOLT for an underlying asset
    /// @dev does not require non-reentrant modifier because this contract
    /// stores no state. Even if USDC, DAI or any other token this contract uses
    /// had an after transfer hook, calling mint or redeem in a reentrant fashion
    /// would not allow any theft of funds, it would simply build up a call stack
    /// of orders that would need to be executed.
    /// @param to recipient of underlying tokens
    /// @param amountVoltIn amount of volt to sell
    /// @param minAmountOut of underlying tokens sent to recipient
    function redeem(
        address to,
        uint256 amountVoltIn,
        uint256 minAmountOut
    ) external override globalLock(1) returns (uint256 amountOut) {
        /// ------- Checks -------
        /// 1. current price from oracle is correct
        /// 2. how much underlying token to receive
        /// 3. underlying token to receive meets min amount out

        amountOut = getRedeemAmountOut(amountVoltIn);
        require(
            amountOut >= minAmountOut,
            "PegStabilityModule: Redeem not enough out"
        );

        /// ------- Effects / Interactions with Internal Contracts -------

        /// Do effect after interaction because you don't want to give tokens before
        /// taking the corresponding amount of Volt from the account.
        /// Replenishing buffer allows more Volt to be minted.
        volt().burnFrom(msg.sender, amountVoltIn); /// Check and Interaction with a trusted contract
        globalRateLimitedMinter().replenishBuffer(amountVoltIn); /// Effect -- interaction with a trusted contract

        /// ------- Interaction with External Contract -------

        underlyingToken.safeTransfer(to, amountOut); /// Interaction -- untrusted contract

        emit Redeem(to, amountVoltIn, amountOut);
    }

    /// @notice function to buy VOLT for an underlying asset
    /// This contract has no minting functionality, so the max
    /// amount of Volt that can be purchased is the Volt balance in the contract
    /// @dev does not require non-reentrant modifier because this contract
    /// stores no state. Even if USDC, DAI or any other token this contract uses
    /// had an after transfer hook, calling mint or redeem in a reentrant fashion
    /// would not allow any theft of funds, it would simply build up a call stack
    /// of orders that would need to be executed.
    /// @param to recipient of the Volt
    /// @param amountIn amount of underlying tokens used to purchase Volt
    /// @param minAmountVoltOut minimum amount of Volt recipient to receive
    function mint(
        address to,
        uint256 amountIn,
        uint256 minAmountVoltOut
    ) external override globalLock(1) returns (uint256 amountVoltOut) {
        /// ------- Checks -------
        /// 1. current price from oracle is correct
        /// 2. how much volt to receive
        /// 3. volt to receive meets min amount out

        amountVoltOut = getMintAmountOut(amountIn);
        require(
            amountVoltOut >= minAmountVoltOut,
            "PegStabilityModule: Mint not enough out"
        );

        /// ------- Check / Effect / Trusted Interaction -------

        /// Checks that there is enough Volt left to mint globally.
        /// This is a check as well, because if there isn't sufficient Volt to mint,
        /// then, the call to mintVolt will fail in the RateLimitedV2 class.
        globalRateLimitedMinter().mintVolt(to, amountVoltOut); /// Check, Effect, then Interaction with trusted contract

        /// ------- Interactions with Untrusted Contract -------

        underlyingToken.safeTransferFrom(msg.sender, address(this), amountIn); /// Interaction -- untrusted contract

        emit Mint(to, amountIn, amountVoltOut);
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
    ) public view override returns (uint256 amountVoltOut) {
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

    /// @notice returns the maximum amount of Volt that can be minted
    function getMaxMintAmountOut() external view override returns (uint256) {
        return globalRateLimitedMinter().buffer();
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
