pragma solidity 0.8.13;

contract MockCToken {
    address public underlying;

    constructor(address _underlying) {
        underlying = _underlying;
    }
}
