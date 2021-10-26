// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../pcv/IPCVDeposit.sol";

/**
 @title Fei Peg Stability Module
 @author Fei Protocol

 The Fei PSM is a contract which holds a reserve of assets in order to exchange FEI at $1 of underlying assets with a fee.
 * `mint()` - buy FEI for $1 of underlying tokens
 * `redeem()` - sell FEI back for $1 of the same

 The contract has a reservesThreshold() of underlying meant to stand ready for redemptions. Any surplus reserves can be sent into the PCV using `allocateSurplus()`

 The contract is a 
 * PCVDeposit - to track reserves
 * OracleRef - to determine price of underlying, and 
 * RateLimitedMinter - to stop infinite mints and related issues.

 Idea inspired by MakerDAO PSM, code written without reference
 */
interface IPegStabilityModule {
    
    // ----------- State changing Api -----------

    /// @notice mint `amountFeiOut` FEI to address `to` for `amountIn` underlying tokens
    /// @dev see getMintAmountOut() to pre-calculate amount out
    function mint(address to, uint256 amountIn)
        external
        payable
        returns (uint256 amountFeiOut);

    /// @notice redeem `amountFeiIn` FEI for `amountOut` underlying tokens and send to address `to` 
    /// @dev see getRedeemAmountOut() to pre-calculate amount out
    function redeem(address to, uint256 amountFeiIn)
        external
        returns (uint256 amountOut);

    /// @notice send any surplus reserves to the PCV allocation
    function allocateSurplus() external;

    // ----------- Governor or admin only state changing api -----------

    /// @notice set the mint fee vs oracle price in basis point terms
    function setMintFee(uint256 newMintFeeBasisPoints) external;

    /// @notice set the redemption fee vs oracle price in basis point terms
    function setRedeemFee(uint256 newRedeemFeeBasisPoints) external;

    /// @notice set the ideal amount of reserves for the contract to hold for redemptions
    function setReservesThreshold(uint256 newReservesThreshold) external;

    /// @notice set the target for sending surplus reserves
    function setTarget(IPCVDeposit newTarget) external;

    // ----------- Getters -----------

    /// @notice calculate the amount of FEI out for a given `amountIn` of underlying
    function getMintAmountOut(uint256 amountIn)
        external
        view
        returns (uint256 amountFeiOut);

    /// @notice calculate the amount of underlying out for a given `amountFeiIn` of FEI
    function getRedeemAmountOut(uint256 amountFeiIn)
        external
        view
        returns (uint256 amountOut);

    /// @notice a flag for whether the current balance is above (true) or below (false) the reservesThreshold
    function hasSurplus() external view returns (bool);

    /// @notice an integer representing the positive surplus or negative deficit of contract balance vs reservesThreshold
    function reservesSurplus() external view returns (int256);

    /// @notice the ideal amount of reserves for the contract to hold for redemptions
    function reservesThreshold() external view returns (uint256);

    /// @notice the mint fee vs oracle price in basis point terms
    function mintFeeBasisPoints() external view returns (uint256);

    /// @notice the redemption fee vs oracle price in basis point terms
    function redeemFeeBasisPoints() external view returns (uint256);

    /// @notice the underlying token exchanged for FEI
    function token() external view returns (IERC20);

    /// @notice the PCV deposit target to send surplus reserves
    function target() external view returns (IPCVDeposit);

    // ----------- Events -----------

    /// @notice event emitted when a new mint fee is set
    event MintFeeUpdate(uint256 oldMintFee, uint256 newMintFee);

    /// @notice event emitted when a new redeem fee is set
    event RedeemFeeUpdate(uint256 oldRedeemFee, uint256 newRedeemFee);

    /// @notice event emitted when reservesThreshold is updated
    event ReservesThresholdUpdate(uint256 oldReservesThreshold, uint256 newReservesThreshold);

    /// @notice event emitted when target is updated
    event TargetUpdate(IPCVDeposit oldTarget, IPCVDeposit newTarget);

    /// @notice event emitted upon a redemption
    event Redeem(address to, uint256 amountFeiIn);

    /// @notice event emitted when fei gets minted
    event Mint(address to, uint256 amountIn);
}
