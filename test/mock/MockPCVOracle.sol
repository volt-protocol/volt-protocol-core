pragma solidity 0.8.13;

contract MockPCVOracle {
    int256 public pcvAmount;
    int256 public profitAmount;

    /// @notice hook on PCV deposit, callable when pcv oracle is set
    /// updates the oracle with the new liquid balance delta
    function updateBalance(int256 deltaBalance, int256 deltaProfit) external {
        pcvAmount += deltaBalance;
        profitAmount += deltaProfit;
    }
}
