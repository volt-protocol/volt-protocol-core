pragma solidity 0.8.13;

contract MockPCVOracle {
    int256 public pcvAmount;

    /// @notice hook on PCV deposit, callable when pcv oracle is set
    /// updates the oracle with the new liquid balance delta
    function updateLiquidBalance(int256 pcvDelta) external {
        pcvAmount += pcvDelta;
    }
}
