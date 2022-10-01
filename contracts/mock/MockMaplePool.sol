pragma solidity =0.8.13;

contract MockMaplePool {
    address public liquidityAsset;

    constructor(address _liquidityAsset) {
        liquidityAsset = _liquidityAsset;
    }
}
