// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {console} from "@forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Constants} from "@voltprotocol/Constants.sol";
import {OracleRefV2} from "@voltprotocol/refs/OracleRefV2.sol";
import {CoreRefV2} from "@voltprotocol/refs/CoreRefV2.sol";
import {IPCVDepositV2} from "@voltprotocol/pcv/IPCVDepositV2.sol";
import {INonCustodialPSM} from "@voltprotocol/peg/INonCustodialPSM.sol";

/// @notice this contract needs the PCV controller role to be able to pull funds
/// from the PCV deposit smart contract.
/// @dev This contract requires the RATE_LIMIT_SYSTEM_ENTRY_REPLENISH_ROLE
/// in order to replenish the buffer in the GlobalRateLimitedMinter.
/// @dev This contract requires the RATE_LIMIT_SYSTEM_EXIT_DEPLETE_ROLE
/// in order to deplete the buffer in the GlobalSystemExitRateLimiter.
/// This PSM is not a PCV deposit because it never holds funds, it only has permissions
/// to pull funds from a pcv deposit and replenish a global buffer.
contract NonCustodialPSM is INonCustodialPSM, OracleRefV2 {
    using SafeERC20 for IERC20;
    using SafeCast for *;

    /// @notice the token this PSM will exchange for VOLT
    IERC20 public immutable override underlyingToken;

    /// @notice the minimum acceptable oracle price floor
    uint128 public override floor;

    /// @notice the maximum acceptable oracle price ceiling
    uint128 public override ceiling;

    /// @notice reference to the fully liquid venue redemptions can occur in
    IPCVDepositV2 public pcvDeposit;

    /// @notice construct the PSM
    /// @param coreAddress reference to core
    /// @param oracleAddress reference to oracle
    /// @param backupOracleAddress reference to backup oracle
    /// @param decimalNormalizer decimal normalizer for oracle price
    /// @param invert invert oracle price
    /// @param underlyingTokenAddress this psm uses
    /// @param floorPrice minimum acceptable oracle price
    /// @param ceilingPrice maximum acceptable oracle price
    constructor(
        address coreAddress,
        address oracleAddress,
        address backupOracleAddress,
        int256 decimalNormalizer,
        bool invert,
        IERC20 underlyingTokenAddress,
        uint128 floorPrice,
        uint128 ceilingPrice,
        IPCVDepositV2 pcvDepositAddress
    )
        OracleRefV2(
            coreAddress,
            oracleAddress,
            backupOracleAddress,
            decimalNormalizer,
            invert
        )
    {
        underlyingToken = underlyingTokenAddress;

        _setPCVDeposit(pcvDepositAddress);
        _setCeiling(ceilingPrice);
        _setFloor(floorPrice);
    }

    // ----------- Governor Only State Changing API -----------

    /// @notice set the target for sending all PCV
    /// @param newTarget new PCV Deposit target for this PSM
    /// enforces that underlying on this PSM and new Deposit are the same
    function setPCVDeposit(
        IPCVDepositV2 newTarget
    ) external override onlyGovernor {
        _setPCVDeposit(newTarget);
    }

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

        /// ------- Check / Effects / Trusted Interactions -------

        /// Do effect after interaction because you don't want to give tokens before
        /// taking the corresponding amount of Volt from the account.
        /// Replenishing buffer allows more Volt to be minted.
        /// None of these three external calls make calls external to the Volt System.
        volt().burnFrom(msg.sender, amountVoltIn); /// Check and Effect -- trusted contract
        globalRateLimitedMinter().replenishBuffer(amountVoltIn); /// Effect -- trusted contract

        /// Interaction -- pcv deposit is trusted,
        /// however this interacts with external untrusted contracts to withdraw funds from a venue
        /// and then transfer an untrusted token to the recipient
        pcvDeposit.withdraw(to, amountOut);

        /// No PCV Oracle hooks needed here as PCV deposit will update PCV Oracle

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

        underlyingToken.safeTransferFrom(
            msg.sender,
            address(pcvDeposit),
            amountIn
        ); /// Interaction -- untrusted contract
        pcvDeposit.deposit(); /// deposit into underlying venue to register new amount of PCV

        emit Mint(to, amountIn, amountVoltOut);
    }

    /// ----------- Public View-Only API ----------

    /// @notice returns the maximum amount of Volt that can be redeemed
    /// with the current PCV Deposit balance and the Global System Exit Rate Limit Buffer
    function getMaxRedeemAmountIn() external view override returns (uint256) {
        /// usdc decimals normalizer: -12
        /// readOracle returns volt price / 1e12
        ///   1.06e18 / 1e12 = 1.06e6
        /// balance returns underlying token balance of usdc
        ///   10_000e6 usdc
        /// 10_000e6 * 1e18 / 1.06e6
        ///   = 9.433962264E21 Volt

        /// dai decimals normalizer: 0
        /// readOracle returns volt price
        ///   1.06e18 = 1.06e18
        /// balance returns underlying token balance of dai
        ///   10_000e18 dai
        /// 10_000e18 * 1e18 / 1.06e18
        ///   = 9.433962264E21 Volt

        uint256 oraclePrice = readOracle();

        /// amount of Volt that can exit the system through the exit rate limiter
        uint256 bufferAllowableVoltAmountOut = (globalRateLimitedMinter()
            .buffer() * Constants.ETH_GRANULARITY) / oraclePrice;

        /// amount of Volt that can exit the system through the pcv deposit
        uint256 pcvDepositAllowableVoltAmountOut = (pcvDeposit.balance() *
            Constants.ETH_GRANULARITY) / oraclePrice;

        /// return the minimum of the pcv deposit balance and the buffer on exiting the system
        return
            Math.min(
                pcvDepositAllowableVoltAmountOut,
                bufferAllowableVoltAmountOut
            );
    }

    /// @notice returns inverse of normal value.
    /// Used to normalize decimals to properly deplete
    /// the buffer in Global System Exit Rate Limiter
    /// @param amount to normalize
    /// @return normalized amount
    function getExitValue(uint256 amount) public view returns (uint256) {
        uint256 scalingFactor;

        if (decimalsNormalizer == 0) {
            return amount;
        }
        if (decimalsNormalizer < 0) {
            scalingFactor = 10 ** uint256(-decimalsNormalizer);
            return amount * scalingFactor;
        } else {
            scalingFactor = 10 ** uint256(decimalsNormalizer);
            return amount / scalingFactor;
        }
    }

    /// ----------- Public View-Only API ----------

    /// @notice return address of token
    function token() public view returns (address) {
        return address(underlyingToken);
    }

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

    /// @notice returns whether or not the current price is valid
    function isPriceValid() external view override returns (bool) {
        return _validPrice(readOracle());
    }

    /// ----------- Private Helper Functions -----------

    /// @notice helper function to set the PCV deposit
    /// @param newPCVDeposit the new PCV deposit that this PSM will pull assets from and deposit assets into
    function _setPCVDeposit(IPCVDepositV2 newPCVDeposit) private {
        require(
            newPCVDeposit.token() == address(underlyingToken),
            "PegStabilityModule: Underlying token mismatch"
        );
        IPCVDepositV2 oldTarget = pcvDeposit;
        pcvDeposit = newPCVDeposit;

        emit PCVDepositUpdate(address(oldTarget), address(newPCVDeposit));
    }

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
