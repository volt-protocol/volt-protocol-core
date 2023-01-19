pragma solidity =0.8.13;

contract MockPSM {
    address public underlying;

    constructor(address _underlying) {
        underlying = _underlying;
    }

    function setUnderlying(address newUnderlying) external {
        underlying = newUnderlying;
    }

    function balanceReportedIn() external view returns (address) {
        return underlying;
    }
}
