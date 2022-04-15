// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

contract MockChainlinkToken {
    function transferAndCall(
        address,
        uint256,
        bytes calldata
    ) external returns (bool success) {
        return true;
    }
}
