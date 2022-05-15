// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import {IVolt} from "../volt/IVolt.sol";

interface IUSDC is IVolt {
    function masterMinter() external view returns (address);

    function configureMinter(address minter, uint256 minterAllowedAmount)
        external
        view
        returns (bool);
}
