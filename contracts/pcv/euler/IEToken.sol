pragma solidity =0.8.13;

interface IEToken {
    /// @notice withdraw from euler
    function withdraw(uint256 subAccountId, uint256 amount) external;

    /// @notice deposit into euler
    function deposit(uint256 subAccountId, uint256 amount) external;

    /// @notice returns balance of underlying including all interest accrued
    function balanceOfUnderlying(address account)
        external
        view
        returns (uint256);

    /// @notice returns address of underlying token
    function underlyingAsset() external view returns (address);

    /// @notice returns balance of address
    function balanceOf(address) external view returns (uint256);
}
