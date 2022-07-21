// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface ICurveFactory {
    function find_pool_for_coins(address _from, address _to)
        external
        returns (address);
}
