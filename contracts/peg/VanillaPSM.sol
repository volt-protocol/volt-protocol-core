// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {BasePSM} from "./BasePSM.sol";
import {IPCVDeposit} from "../pcv/IPCVDeposit.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract VanillaPSM is BasePSM {
    constructor(OracleParams memory params, IERC20 _underlyingToken)
        BasePSM(params, _underlyingToken)
    {}
}
