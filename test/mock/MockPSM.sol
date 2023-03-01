pragma solidity =0.8.13;

contract MockPSM {
    address public token;

    constructor(address _token) {
        token = _token;
    }

    function setUnderlying(address newUnderlying) external {
        token = newUnderlying;
    }

    function balanceReportedIn() external view returns (address) {
        return token;
    }
}
