// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {ICore} from "./../core/Core.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice contract that streams payment to Volt Protocol based
/// on the amount of Fei the VCON DAO holds
/// @notice any governor in the Fei System can claw back the unvested Fei.
interface IFeiSavingsRate {
    // ----------- Getters -----------

    /// @notice returns the address that receives the proceeds from the Fei interest
    function recipient() external view returns (address);

    /// @notice the annual interest rate earned on all Fei held in the feiHolder contract
    /// this is simple interest, measured as APR, not APY
    function basisPointsPayout() external view returns (uint256);

    /// @notice the address of the contract that will hold Fei that interest is paid on
    function feiHolder() external view returns (address);

    /// @notice reference to the Fei Core contract
    /// Any governor in the Fei System can claw back the unvested Fei.
    function feiCore() external view returns (ICore);

    /// @notice reference to the Fei ERC20 token implementation
    function fei() external view returns (IERC20);

    /// @notice the last amount of Fei the Volt Protocol smart contract held
    function lastFeiAmount() external view returns (uint216);

    /// @notice the last block timestamp where payouts occurred
    function lastRecordedPayout() external view returns (uint40);

    // ----------- Events -----------

    /// @notice event emitted when a clawback occurs
    event Clawback(uint256 amount);

    /// @notice event emitted when interest is paid to the VCON DAO
    event InterestPaid(uint256 amount);

    // ----------- State changing API -----------

    /// @notice function that accrues and then pays out interest based on the amount of Fei Held
    /// records the new
    function earnInterest() external;

    /// @notice function that the Tribe DAO governor can call to cancel the FSR for Volt
    /// this removes all Fei from the FSR contract and sends that Fei to the caller
    function clawback() external;
}
