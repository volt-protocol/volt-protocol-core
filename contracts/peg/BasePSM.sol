// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./../pcv/PCVDeposit.sol";
import "./IBasePSM.sol";
import "./../refs/OracleRef.sol";
import "../Constants.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

abstract contract BasePSM is IBasePSM, OracleRef, PCVDeposit {
    using Decimal for Decimal.D256;
    using SafeCast for *;
    using SafeERC20 for IERC20;

    /// @notice the amount of reserves to be held for redemptions
    uint256 public override reservesThreshold;

    /// @notice the PCV deposit target
    IPCVDeposit public override surplusTarget;

    /// @notice the token this PSM will exchange for VOLT
    IERC20 public immutable override underlyingToken;

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
    constructor(
        OracleParams memory params,
        uint256 _reservesThreshold,
        IERC20 _underlyingToken,
        IPCVDeposit _surplusTarget
    )
        OracleRef(
            params.coreAddress,
            params.oracleAddress,
            params.backupOracle,
            params.decimalsNormalizer,
            params.doInvert
        )
    {
        underlyingToken = _underlyingToken;

        _setReservesThreshold(_reservesThreshold);
        _setSurplusTarget(_surplusTarget);
        _setContractAdminRole(keccak256("PSM_ADMIN_ROLE"));
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

    /// @notice set the ideal amount of reserves for the contract to hold for redemptions
    function setReservesThreshold(uint256 newReservesThreshold)
        external
        override
        onlyGovernorOrAdmin
    {
        _setReservesThreshold(newReservesThreshold);
    }

    /// @notice set the target for sending surplus reserves
    function setSurplusTarget(IPCVDeposit newTarget)
        external
        override
        onlyGovernorOrAdmin
    {
        _setSurplusTarget(newTarget);
    }

    /// @notice helper function to set reserves threshold
    function _setReservesThreshold(uint256 newReservesThreshold) internal {
        require(
            newReservesThreshold > 0,
            "PegStabilityModule: Invalid new reserves threshold"
        );
        uint256 oldReservesThreshold = reservesThreshold;
        reservesThreshold = newReservesThreshold;

        emit ReservesThresholdUpdate(
            oldReservesThreshold,
            newReservesThreshold
        );
    }

    /// @notice helper function to set the surplus target
    function _setSurplusTarget(IPCVDeposit newSurplusTarget) internal {
        require(
            address(newSurplusTarget) != address(0),
            "PegStabilityModule: Invalid new surplus target"
        );
        require(
            newSurplusTarget.balanceReportedIn() == address(underlyingToken),
            "PegStabilityModule: Underlying token mismatch"
        );

        IPCVDeposit oldTarget = surplusTarget;
        surplusTarget = newSurplusTarget;

        emit SurplusTargetUpdate(oldTarget, newSurplusTarget);
    }

    // ----------- Public State Changing API -----------

    /// @notice send any surplus reserves to the PCV allocation
    function allocateSurplus() external override {
        int256 currentSurplus = reservesSurplus();
        require(
            currentSurplus > 0,
            "PegStabilityModule: No surplus to allocate"
        );

        _allocate(currentSurplus.toUint256());
    }

    /// @notice function to receive ERC20 tokens from external contracts
    function deposit() external override {
        int256 currentSurplus = reservesSurplus();
        if (currentSurplus > 0) {
            _allocate(currentSurplus.toUint256());
        }
    }

    /// @notice function to redeem VOLT for an underlying asset
    function redeem(
        address to,
        uint256 amountVoltIn,
        uint256 minAmountOut
    ) external virtual override whenNotPaused returns (uint256 amountOut) {
        amountOut = _getRedeemAmountOut(amountVoltIn);
        require(
            amountOut >= minAmountOut,
            "PegStabilityModule: Redeem not enough out"
        );

        _beforeVoltRedeem(to, amountVoltIn, minAmountOut);

        IERC20(volt()).safeTransferFrom(
            msg.sender,
            address(this),
            amountVoltIn
        );

        SafeERC20.safeTransfer(underlyingToken, to, amountOut);

        emit Redeem(to, amountVoltIn, amountOut);

        _afterVoltRedeem(to, amountVoltIn, minAmountOut);
    }

    /// @notice function to buy VOLT for an underlying asset
    function mint(
        address to,
        uint256 amountIn,
        uint256 minAmountVoltOut
    ) external virtual override whenNotPaused returns (uint256 amountVoltOut) {
        amountVoltOut = _getMintAmountOut(amountIn);
        require(
            amountVoltOut >= minAmountVoltOut,
            "PegStabilityModule: Mint not enough out"
        );

        _beforeVoltMint(to, amountIn, minAmountVoltOut);

        SafeERC20.safeTransferFrom(
            underlyingToken,
            msg.sender,
            address(this),
            amountIn
        );

        uint256 amountVoltToTransfer = Math.min(
            volt().balanceOf(address(this)),
            amountVoltOut
        );

        if (amountVoltToTransfer != 0) {
            IERC20(volt()).safeTransfer(to, amountVoltToTransfer);
        }

        _afterVoltMint(to, amountIn, minAmountVoltOut);
    }

    // ----------- Public View-Only API ----------

    /// @notice calculate the amount of VOLT out for a given `amountIn` of underlying
    /// First get oracle price of token
    /// Then figure out how many dollars that amount in is worth by multiplying price * amount.
    /// ensure decimals are normalized if on underlying they are not 18
    function getMintAmountOut(uint256 amountIn)
        public
        view
        override
        returns (uint256 amountVoltOut)
    {
        amountVoltOut = _getMintAmountOut(amountIn);
    }

    /// @notice calculate the amount of underlying out for a given `amountVoltIn` of VOLT
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

    /// @notice a flag for whether the current balance is above (true) or below (false) the reservesThreshold
    function hasSurplus() external view override returns (bool) {
        return balance() > reservesThreshold;
    }

    /// @notice an integer representing the positive surplus or negative deficit of contract balance vs reservesThreshold
    function reservesSurplus() public view override returns (int256) {
        return balance().toInt256() - reservesThreshold.toInt256();
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

    // ----------- Internal Methods -----------

    /// @notice helper function to get mint amount out based on current market prices
    /// @dev will revert if price is outside of bounds and bounded PSM is being used
    function _getMintAmountOut(uint256 amountIn)
        internal
        view
        virtual
        returns (uint256 amountVoltOut)
    {
        Decimal.D256 memory oraclePrice = readOracle();
        _validatePriceRange(oraclePrice);

        uint256 voltPrice = oraclePrice.asUint256();

        amountVoltOut = amountIn / voltPrice;
    }

    /// @notice helper function to get redeem amount out based on current market prices
    /// @dev will revert if price is outside of bounds and bounded PSM is being used
    function _getRedeemAmountOut(uint256 amountVoltIn)
        internal
        view
        virtual
        returns (uint256 amountTokenOut)
    {
        Decimal.D256 memory oraclePrice = readOracle();
        _validatePriceRange(oraclePrice);

        uint256 voltPrice = oraclePrice.asUint256();

        amountTokenOut = amountVoltIn * voltPrice;
    }

    /// @notice Allocates a portion of escrowed PCV to a target PCV deposit
    function _allocate(uint256 amount) internal virtual {
        SafeERC20.safeTransfer(underlyingToken, address(surplusTarget), amount);

        surplusTarget.deposit();

        emit AllocateSurplus(msg.sender, amount);
    }

    // ----------- Hooks -----------

    /// @notice overriden function in the bounded PSM
    function _validatePriceRange(Decimal.D256 memory price)
        internal
        view
        virtual
    {}

    /// @dev Hook that is called before VOLT is minted
    //  to is the address VOLT is being minted to
    //  amountIn is the the amount of stablecoin beind deposited
    //  minAmountOut is minimum amount of VOLT to be received

    function _beforeVoltMint(
        address to,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal virtual {}

    /**
     * @dev Hook that is called after VOLT is minted
     *  to is the address VOLT is being minted to
     *  amountIn is the the amount of underyling stablecoin beind deposited
     *  minAmountOut is minimum amount of VOLT to be received
     */
    function _afterVoltMint(
        address to,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal virtual {}

    /// @dev Hook that is called before VOLT is redeemed
    //  to is the address in which the underlying stablecoin will be sent to when VOLT redeemed
    //  amountVoltIn is the the amount of VOLT beind deposited
    //  minAmountOut is minimum amount of underlying stablecoin to be received
    function _beforeVoltRedeem(
        address to,
        uint256 amountVoltIn,
        uint256 minAmountOut
    ) internal virtual {}

    /// @dev Hook that is called after VOLT is redeemed
    //  to is the address in which the underlying stablecoin will be sent to when VOLT redeemed
    //  amountVoltIn is the the amount of VOLT beind deposited
    //  minAmountOut is minimum amount of underlying stablecoin to be received

    function _afterVoltRedeem(
        address to,
        uint256 amountVoltIn,
        uint256 minAmountOut
    ) internal virtual {}
}
