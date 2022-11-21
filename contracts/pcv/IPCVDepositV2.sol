// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IPCVDeposit} from "./IPCVDeposit.sol";

/// @title PCV V2 Deposit interface
/// @author Volt Protocol
interface IPCVDepositV2 is IPCVDeposit {
    // ----------- State changing api -----------

    function harvest() external;

    function accrue() external returns (uint256);
}
