// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Decimal} from "../external/Decimal.sol";
import {Constants} from "../Constants.sol";
import {OracleRef} from "./../refs/OracleRef.sol";
import {PCVDeposit} from "./../pcv/PCVDeposit.sol";
import {IPCVDeposit} from "./../pcv/IPCVDeposit.sol";
import {IPegStabilityModule} from "./IPegStabilityModule.sol";

contract PegStabilityModule is
    IPegStabilityModule,
    OracleRef,
    PCVDeposit,
    ReentrancyGuard
{
    using Decimal for Decimal.D256;
    using SafeCast for *;
    using SafeERC20 for IERC20;

    /// @notice the token this PSM will exchange for VOLT
    /// This token will be set to WETH9 if the bonding curve accepts eth
    IERC20 public immutable override underlyingToken;

    /// @notice boolean switch that indicates whether redemptions are paused
    bool public redeemPaused;

    /// @notice event that is emitted when redemptions are paused
    event RedemptionsPaused(address account);

    /// @notice event that is emitted when redemptions are unpaused
    event RedemptionsUnpaused(address account);

    /// @notice boolean switch that indicates whether minting is paused
    bool public mintPaused;

    /// @notice event that is emitted when minting is paused
    event MintingPaused(address account);

    /// @notice event that is emitted when minting is unpaused
    event MintingUnpaused(address account);

    /// @notice struct for passing constructor parameters related to OracleRef
    struct OracleParams {
        address coreAddress;
        address oracleAddress;
        address backupOracle;
        int256 decimalsNormalizer;
        bool doInvert;
    }

    /// @notice constructor
    /// @param params PSM constructor parameter struct
    constructor(OracleParams memory params, IERC20 _underlyingToken)
        OracleRef(
            params.coreAddress,
            params.oracleAddress,
            params.backupOracle,
            params.decimalsNormalizer,
            params.doInvert
        )
    {
        underlyingToken = _underlyingToken;
    }

    /// @notice modifier that allows execution when redemptions are not paused
    modifier whileRedemptionsNotPaused() {
        require(!redeemPaused, "PegStabilityModule: Redeem paused");
        _;
    }

    /// @notice modifier that allows execution when minting is not paused
    modifier whileMintingNotPaused() {
        require(!mintPaused, "PegStabilityModule: Minting paused");
        _;
    }

    /// @notice set secondary pausable methods to paused
    function pauseRedeem() external onlyGuardianOrGovernor {
        redeemPaused = true;
        emit RedemptionsPaused(msg.sender);
    }

    /// @notice set secondary pausable methods to unpaused
    function unpauseRedeem() external onlyGuardianOrGovernor {
        redeemPaused = false;
        emit RedemptionsUnpaused(msg.sender);
    }

    /// @notice set secondary pausable methods to paused
    function pauseMint() external onlyGuardianOrGovernor {
        mintPaused = true;
        emit MintingPaused(msg.sender);
    }

    /// @notice set secondary pausable methods to unpaused
    function unpauseMint() external onlyGuardianOrGovernor {
        mintPaused = false;
        emit MintingUnpaused(msg.sender);
    }

    /// @notice withdraw assets from PSM to an external address
    function withdraw(address to, uint256 amount)
        external
        virtual
        override
        onlyPCVController
    {
        _withdrawERC20(address(underlyingToken), to, amount);
    }

    /// @notice internal helper method to redeem Volt in exchange for an external asset
    function _redeem(
        address to,
        uint256 amountVoltIn,
        uint256 minAmountOut
    ) internal virtual returns (uint256 amountOut) {
        updateOracle();

        amountOut = _getRedeemAmountOut(amountVoltIn);
        require(
            amountOut >= minAmountOut,
            "PegStabilityModule: Redeem not enough out"
        );

        IERC20(volt()).safeTransferFrom(
            msg.sender,
            address(this),
            amountVoltIn
        );

        _transfer(to, amountOut);

        emit Redeem(to, amountVoltIn, amountOut);
    }

    /// @notice internal helper method to mint Volt in exchange for an external asset
    function _mint(
        address to,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal virtual returns (uint256 amountVoltOut) {
        updateOracle();

        amountVoltOut = _getMintAmountOut(amountIn);
        require(
            amountVoltOut >= minAmountOut,
            "PegStabilityModule: Mint not enough out"
        );

        _transferFrom(msg.sender, address(this), amountIn);

        IERC20(volt()).safeTransfer(to, amountVoltOut);

        emit Mint(to, amountIn, amountVoltOut);
    }

    /// @notice function to redeem VOLT for an underlying asset
    /// @param to recipient of underlying tokens
    /// @param amountVoltIn amount of volt to sell
    /// @param minAmountOut of underlying tokens sent to recipient
    function redeem(
        address to,
        uint256 amountVoltIn,
        uint256 minAmountOut
    )
        external
        virtual
        override
        nonReentrant
        whenNotPaused
        whileRedemptionsNotPaused
        returns (uint256 amountOut)
    {
        amountOut = _redeem(to, amountVoltIn, minAmountOut);
    }

    /// @notice function to buy VOLT for an underlying asset
    /// This contract has no minting functionality, so the max
    /// amount of Volt that can be purchased is the Volt balance in the contract
    /// @param to recipient of the Volt
    /// @param amountIn amount of underlying tokens used to purchase Volt
    /// @param minAmountOut minimum amount of Volt recipient to receive
    function mint(
        address to,
        uint256 amountIn,
        uint256 minAmountOut
    )
        external
        virtual
        override
        nonReentrant
        whenNotPaused
        whileMintingNotPaused
        returns (uint256 amountVoltOut)
    {
        amountVoltOut = _mint(to, amountIn, minAmountOut);
    }

    /// ----------- Public View-Only API ----------

    /// @notice calculate the amount of VOLT out for a given `amountIn` of underlying
    /// First get oracle price of token
    /// Then figure out how many dollars that amount in is worth by multiplying price * amount.
    /// ensure decimals are normalized if on underlying they are not 18
    /// @param amountIn amount of underlying token in
    /// @return amountVoltOut the amount of Volt out
    function getMintAmountOut(uint256 amountIn)
        public
        view
        override
        returns (uint256 amountVoltOut)
    {
        amountVoltOut = _getMintAmountOut(amountIn);
    }

    /// @notice calculate the amount of underlying out for a given `amountVoltIn` of Volt
    /// First get oracle price of token
    /// Then figure out how many dollars that amount in is worth by multiplying price * amount.
    /// ensure decimals are normalized if on underlying they are not 18
    function getRedeemAmountOut(uint256 amountVoltIn)
        public
        view
        override
        returns (uint256 amountTokenOut)
    {
        amountTokenOut = _getRedeemAmountOut(amountVoltIn);
    }

    /// @notice the maximum mint amount out
    function getMaxMintAmountOut() external view override returns (uint256) {
        return volt().balanceOf(address(this));
    }

    /// @notice function from PCVDeposit that must be overriden
    function balance() public view virtual override returns (uint256) {
        return underlyingToken.balanceOf(address(this));
    }

    /// @notice returns address of token this contracts balance is reported in
    function balanceReportedIn() public view override returns (address) {
        return address(underlyingToken);
    }

    /// @notice override default behavior of not checking Volt balance
    function resistantBalanceAndVolt()
        public
        view
        override
        returns (uint256, uint256)
    {
        return (balance(), voltBalance());
    }

    /// ----------- Internal Methods -----------

    /// @notice helper function to get mint amount out based on current market prices
    /// @dev will revert if price is outside of bounds and bounded PSM is being used
    function _getMintAmountOut(uint256 amountIn)
        internal
        view
        virtual
        returns (uint256 amountVoltOut)
    {
        Decimal.D256 memory price = readOracle();
        _validatePriceRange(price);

        Decimal.D256 memory adjustedAmountIn = price.mul(amountIn);

        amountVoltOut = adjustedAmountIn.asUint256();
    }

    /// @notice helper function to get redeem amount out based on current market prices
    /// @dev will revert if price is outside of bounds and bounded PSM is being used
    function _getRedeemAmountOut(uint256 amountVoltIn)
        internal
        view
        virtual
        returns (uint256 amountTokenOut)
    {
        Decimal.D256 memory price = readOracle();
        _validatePriceRange(price);

        /// get amount of dollars being provided
        Decimal.D256 memory adjustedAmountIn = Decimal.from(amountVoltIn);

        /// now turn the dollars into the underlying token amounts
        /// dollars / price = how much token to pay out
        amountTokenOut = adjustedAmountIn.div(price).asUint256();
    }

    /// @notice transfer ERC20 token
    function _transfer(address to, uint256 amount) internal {
        SafeERC20.safeTransfer(underlyingToken, to, amount);
    }

    /// @notice transfer assets from user to this contract
    function _transferFrom(
        address from,
        address to,
        uint256 amount
    ) internal {
        SafeERC20.safeTransferFrom(underlyingToken, from, to, amount);
    }

    /// @notice no-op to maintain backwards compatability with IPCVDeposit
    /// pauseable to stop integration if this contract is deprecated
    function deposit() external override whenNotPaused {}

    /// ----------- Hook -----------

    /// @notice overriden function in the bounded PSM
    function _validatePriceRange(Decimal.D256 memory) internal view virtual {}
}
