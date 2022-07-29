// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {IPCVDeposit, PCVDeposit} from "./../pcv/PCVDeposit.sol";
import {IBasePSM} from "./IBasePSM.sol";
import {OracleRef, Decimal, SafeCast} from "./../refs/OracleRef.sol";
import {Constants} from "../Constants.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

abstract contract BasePSM is IBasePSM, OracleRef, PCVDeposit {
    using Decimal for Decimal.D256;
    using SafeCast for *;
    using SafeERC20 for IERC20;

    /// @notice the token this PSM will exchange for VOLT
    IERC20 public immutable override underlyingToken;

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

    /// @notice withdraw assets from PSM to an external address
    function withdraw(address to, uint256 amount)
        external
        override
        onlyPCVController
    {
        _withdrawERC20(address(underlyingToken), to, amount);
    }

    /// @notice function to redeem VOLT for an underlying asset
    function redeem(
        address to,
        uint256 amountVoltIn,
        uint256 minAmountOut
    ) external virtual override whenNotPaused returns (uint256 amountOut) {
        amountOut = getRedeemAmountOut(amountVoltIn);
        require(amountOut >= minAmountOut, "BasePSM: Redeem not enough out");

        _beforeVoltRedeem(to, amountVoltIn, minAmountOut, amountOut);

        IERC20(volt()).safeTransferFrom(
            msg.sender,
            address(this),
            amountVoltIn
        );

        underlyingToken.safeTransfer(to, amountOut);

        emit Redeem(to, amountVoltIn, amountOut);

        _afterVoltRedeem(to, amountVoltIn, minAmountOut, amountOut);
    }

    /// @notice function to buy VOLT for an underlying asset
    function mint(
        address to,
        uint256 amountIn,
        uint256 minAmountVoltOut
    ) external virtual override whenNotPaused returns (uint256 amountVoltOut) {
        amountVoltOut = getMintAmountOut(amountIn);

        require(
            amountVoltOut >= minAmountVoltOut,
            "BasePSM: Mint not enough out"
        );

        _beforeVoltMint(to, amountIn, minAmountVoltOut, amountVoltOut);

        underlyingToken.safeTransferFrom(msg.sender, address(this), amountIn);

        IERC20(volt()).safeTransfer(to, amountVoltOut);

        emit Mint(to, amountIn, amountVoltOut);

        _afterVoltMint(to, amountIn, minAmountVoltOut, amountVoltOut);
    }

    // ----------- Public State Changing API ----------

    /// @notice function to receive ERC20 tokens from external contracts

    function deposit() external virtual override {}

    // ----------- Public View-Only API ----------

    /// @notice calculate the amount of VOLT out for a given `amountIn` of underlying
    /// First get oracle price of token
    /// Then figure out how many dollars that amount in is worth by multiplying price * amount.
    /// ensure decimals are normalized if on underlying they are not 18
    function getMintAmountOut(uint256 amountIn)
        public
        view
        virtual
        override
        returns (uint256 amountVoltOut)
    {
        Decimal.D256 memory oraclePrice = readOracle();
        _validatePriceRange(oraclePrice);

        amountVoltOut = (amountIn * 1e18) / oraclePrice.value;
    }

    /// @notice calculate the amount of underlying out for a given `amountVoltIn` of VOLT
    /// First get oracle price of token
    /// Then figure out how many dollars that amount in is worth by multiplying price * amount.
    /// ensure decimals are normalized if on underlying they are not 18
    function getRedeemAmountOut(uint256 amountVoltIn)
        public
        view
        virtual
        override
        returns (uint256 amountTokenOut)
    {
        Decimal.D256 memory oraclePrice = readOracle();
        _validatePriceRange(oraclePrice);

        amountTokenOut = oraclePrice.mul(amountVoltIn).asUint256();
    }

    /// @notice the maximum mint amount out
    function getMaxMintAmountOut() external view override returns (uint256) {
        return volt().balanceOf(address(this));
    }

    /// @notice the maximum redeem amount out
    function getMaxRedeemAmountOut() external view returns (uint256) {
        return underlyingToken.balanceOf(address(this));
    }

    /// @notice function from PCVDeposit that must be overriden
    function balance() public view virtual override returns (uint256) {
        return underlyingToken.balanceOf(address(this));
    }

    /// @notice returns address of token this contracts balance is reported in
    function balanceReportedIn() public view override returns (address) {
        return address(underlyingToken);
    }

    /// @notice override default behavior of not checking VOLT balance
    function resistantBalanceAndVolt()
        public
        view
        override
        returns (uint256, uint256)
    {
        return (balance(), voltBalance());
    }

    // ----------- Hooks -----------

    /// @notice overriden function in the bounded PSM
    function _validatePriceRange(Decimal.D256 memory price)
        internal
        view
        virtual
    {}

    /// @dev Hook that is called before VOLT is minted
    /// @param to is the address VOLT is being minted to
    /// @param amountIn is the the amount of stablecoin beind deposited
    /// @param minAmountOut is minimum amount of VOLT to be received
    /// @param amountVoltOut the amount of VOLT received from the PSM
    function _beforeVoltMint(
        address to,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 amountVoltOut
    ) internal virtual {}

    /// @dev Hook that is called after VOLT is minted
    /// @param to is the address VOLT is being minted to
    /// @param  amountIn is the the amount of underyling stablecoin beind deposited
    /// @param minAmountOut is minimum amount of VOLT to be received
    /// @param amountVoltOut the amount of VOLT received from the PSM
    function _afterVoltMint(
        address to,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 amountVoltOut
    ) internal virtual {}

    /// @dev Hook that is called before VOLT is redeemed
    /// @param to is the address in which the underlying stablecoin will be sent to when VOLT redeemed
    /// @param amountVoltIn is the the amount of VOLT beind deposited
    /// @param minAmountOut is minimum amount of underlying stablecoin to be received
    function _beforeVoltRedeem(
        address to,
        uint256 amountVoltIn,
        uint256 minAmountOut,
        uint256 amountOut
    ) internal virtual {}

    /// @dev Hook that is called after VOLT is redeemed
    /// @param  to is the address in which the underlying stablecoin will be sent to when VOLT redeemed
    /// @param amountVoltIn is the the amount of VOLT beind deposited
    /// @param minAmountOut is minimum amount of underlying stablecoin to be received
    function _afterVoltRedeem(
        address to,
        uint256 amountVoltIn,
        uint256 minAmountOut,
        uint256 amountOut
    ) internal virtual {}
}
