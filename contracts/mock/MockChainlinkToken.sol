// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

contract MockChainlinkToken {
    uint256 private _x;

    function transferAndCall(
        address,
        uint256,
        bytes calldata
    ) external returns (bool success) {
        _x = 1; /// shhhhh
        return true;
    }
}
