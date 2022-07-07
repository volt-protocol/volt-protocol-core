// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../pcv/IPCVDeposit.sol";

/**
 * @title Volt Base Peg Stability Module
 * @author Volt Protocol
 * @notice  The Volt PSM is a contract which holds a reserve of assets in order to exchange VOLT for underlying assets.
 * `mint()` - buy VOLT with underlying tokens
 * `redeem()` - sell VOLT back for underlying tokens
 *
 * The contract has a reservesThreshold() of underlying meant to stand ready for redemptions. Any surplus reserves can be sent into the PCV using `allocateSurplus()`
 *
 * The contract is a
 * PCVDeposit - to track reserves
 *
 */
interface IBasePSM {
    // ----------- Public State Changing API -----------

    /// @notice mint `amountVoltOut` VOLT to address `to` for `amountIn` underlying tokens
    /// @dev see getMintAmountOut() to pre-calculate amount out
    function mint(
        address to,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountVoltOut);

    /// @notice redeem `amountVoltIn` VOLT for `amountOut` underlying tokens and send to address `to`
    /// @dev see getRedeemAmountOut() to pre-calculate amount out
    function redeem(
        address to,
        uint256 amountVoltIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut);

    /// @notice send any surplus reserves to the PCV allocation
    function allocateSurplus() external;

    // ----------- Governor or Admin Only State Changing API -----------

    /// @notice set the ideal amount of reserves for the contract to hold for redemptions
    function setReservesThreshold(uint256 newReservesThreshold) external;

    /// @notice set the target for sending surplus reserves
    function setSurplusTarget(IPCVDeposit newTarget) external;

    // ----------- Getters -----------

    /// @notice calculate the amount of VOLT out for a given `amountIn` of underlying
    function getMintAmountOut(uint256 amountIn)
        external
        view
        returns (uint256 amountVoltOut);

    /// @notice calculate the amount of underlying out for a given `amountVoltIn` of VOLT
    function getRedeemAmountOut(uint256 amountVoltIn)
        external
        view
        returns (uint256 amountOut);

    /// @notice the maximum mint amount out
    function getMaxMintAmountOut() external view returns (uint256);

    /// @notice a flag for whether the current balance is above (true) or below and equal (false) to the reservesThreshold
    function hasSurplus() external view returns (bool);

    /// @notice an integer representing the positive surplus or negative deficit of contract balance vs reservesThreshold
    function reservesSurplus() external view returns (int256);

    /// @notice the ideal amount of reserves for the contract to hold for redemptions
    function reservesThreshold() external view returns (uint256);

    /// @notice the underlying token exchanged for VOLT
    function underlyingToken() external view returns (IERC20);

    /// @notice the PCV deposit target to send surplus reserves
    function surplusTarget() external view returns (IPCVDeposit);

    // ----------- Events -----------

    /// @notice event emitted when excess PCV is allocated
    event AllocateSurplus(address indexed caller, uint256 amount);

    /// @notice event emitted when reservesThreshold is updated
    event ReservesThresholdUpdate(
        uint256 oldReservesThreshold,
        uint256 newReservesThreshold
    );

    /// @notice event emitted when surplus target is updated
    event SurplusTargetUpdate(IPCVDeposit oldTarget, IPCVDeposit newTarget);

    /// @notice event emitted upon a redemption
    event Redeem(address to, uint256 amountVoltIn, uint256 amountAssetOut);

    /// @notice event emitted when VOLT gets minted
    event Mint(address to, uint256 amountIn, uint256 amountVoltOut);
}
