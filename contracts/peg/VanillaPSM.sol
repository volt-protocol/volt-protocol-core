// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {BasePSM} from "./BasePSM.sol";
import {IPCVDeposit} from "../pcv/IPCVDeposit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract VanillaPSM is BasePSM {
    constructor(
        OracleParams memory params,
        uint256 _reservesThreshold,
        IERC20 _underlyingToken,
        IPCVDeposit _surplusTarget
    ) BasePSM(params, _reservesThreshold, _underlyingToken, _surplusTarget) {}
}
