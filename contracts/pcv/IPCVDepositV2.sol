// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {IPCVDeposit} from "./IPCVDeposit.sol";

/// @title a PCV Deposit interface
/// @author VOLT Protocol
interface IPCVDepositV2 is IPCVDeposit {
    // ----------- PCV Controller only state changing api -----------
    function withdrawAllERC20(address token, address to) external;
}
