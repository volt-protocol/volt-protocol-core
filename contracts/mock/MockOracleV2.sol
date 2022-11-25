// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

contract MockOracleV2 {
    uint256 public price;
    bool public valid;

    function setValues(uint256 value, bool isValid) external {
        price = value;
        valid = isValid;
    }

    function read() external view returns (uint256, bool) {
        return (price, valid);
    }
}
