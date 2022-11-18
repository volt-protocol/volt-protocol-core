// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Decimal} from "../external/Decimal.sol";

contract MockOracle {
    using Decimal for Decimal.D256;

    Decimal.D256 public price;
    bool public valid;

    function setValues(uint256 value, bool isValid) external {
        price = Decimal.from(value).div(1e18);
        valid = isValid;
    }

    function read() external view returns (Decimal.D256 memory, bool) {
        return (price, valid);
    }
}
