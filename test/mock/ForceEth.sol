// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

contract ForceEth {
    constructor() payable {}

    receive() external payable {}

    function forceEth(address to) public {
        selfdestruct(payable(to));
    }
}
