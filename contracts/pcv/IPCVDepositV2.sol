// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

/// @title PCV V2 Deposit interface
/// @author Volt Protocol
interface IPCVDepositV2 {
    // ----------- Events -----------

    event Deposit(address indexed _from, uint256 _amount);

    event Withdrawal(
        address indexed _caller,
        address indexed _to,
        uint256 _amount
    );

    event WithdrawERC20(
        address indexed _caller,
        address indexed _token,
        address indexed _to,
        uint256 _amount
    );

    event WithdrawETH(
        address indexed _caller,
        address indexed _to,
        uint256 _amount
    );

    event Harvest(address indexed _token, int256 _profit, uint256 _timestamp);

    // ----------- PCV Controller only state changing api -----------

    function withdraw(address to, uint256 amount) external;

    function withdrawERC20(address token, address to, uint256 amount) external;

    // ----------- Permissionless State changing api -----------

    /// @notice deposit ERC-20 tokens to underlying venue
    /// non-reentrant to block malicious reentrant state changes
    /// to the lastRecordedBalance variable
    function deposit() external;

    /// @notice claim COMP rewards for supplying to Morpho.
    /// Does not require reentrancy lock as no smart contract state is mutated
    /// in this function.
    function harvest() external;

    /// @notice function that emits an event tracking profits and losses
    /// since the last contract interaction
    /// then writes the current amount of PCV tracked in this contract
    /// to lastRecordedBalance
    /// @return the amount deposited after adding accrued interest or realizing losses
    function accrue() external returns (uint256);

    // ----------- Getters -----------

    /// @notice gets the effective balance of "balanceReportedIn" token if the deposit were fully withdrawn
    function balance() external view returns (uint256);

    /// @notice gets the token address in which this deposit returns its balance
    function balanceReportedIn() external view returns (address);

    /// @notice address of underlying token
    function token() external view returns (address);

    /// @notice address of reward token
    function rewardToken() external view returns (address);
}
