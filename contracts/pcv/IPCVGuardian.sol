// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

/// @title IPCVGuardian
/// @notice an interface for defining how the PCVGuardian functions
/// @dev any implementation of this contract should be granted the roles of Guardian and PCVController in order to work correctly
interface IPCVGuardian {
    // ---------- Events ----------

    event WhitelistAddressAdded(address indexed pcvDeposit);

    event WhitelistAddressRemoved(address indexed pcvDeposit);

    event PCVGuardianWithdrawal(address indexed pcvDeposit, uint256 amount);

    event PCVGuardianERC20Withdrawal(
        address indexed pcvDeposit,
        address token,
        uint256 amount
    );

    // ---------- Read-Only API ----------

    /// @notice returns true if the pcvDeposit address is whitelisted
    /// @param pcvDeposit the address to check
    function isWhitelistAddress(address pcvDeposit)
        external
        view
        returns (bool);

    /// @notice returns all whitelisted addresses
    function getWhitelistAddresses() external view returns (address[] memory);

    // ---------- Governor-Only State-Changing API ----------

    /// @notice governor-only method to whitelist a pcvDeposit address to withdraw funds from
    /// @param pcvDeposit the address to whitelist
    function addWhitelistAddress(address pcvDeposit) external;

    /// @notice batch version of addWhitelistAddress
    /// @param whitelistAddresses the pcvDespoit addresses to whitelist, as calldata
    function addWhitelistAddresses(address[] calldata whitelistAddresses)
        external;

    // ---------- Governor-or-Guardian-Only State-Changing API ----------

    /// @notice governor-or-guardian-only method to remove pcvDeposit address from the whitelist to withdraw funds from
    /// @param pcvDeposit the address to un-whitelist
    function removeWhitelistAddress(address pcvDeposit) external;

    /// @notice batch version of removeWhitelistAddress
    /// @param whitelistAddresses the addresses to un-whitelist
    function removeWhitelistAddresses(address[] calldata whitelistAddresses)
        external;

    /// @notice governor-or-guardian-or-pcv-guard method to withdraw funds from a pcv deposit, by calling the withdraw() method on it
    /// @param pcvDeposit the address of the pcv deposit contract
    /// @param amount the amount to withdraw
    function withdrawToSafeAddress(address pcvDeposit, uint256 amount) external;

    /// @notice governor-or-guardian-or-pcv-guard method to withdraw all at once funds from a pcv deposit, by calling the withdraw() method on it
    /// @param pcvDeposit the address of the pcv deposit contract
    function withdrawAllToSafeAddress(address pcvDeposit) external;

    /// @notice governor-or-guardian-or-pcv-guard method to withdraw an ERC20 from a pcv deposit, by calling the withdrawERC20() method on it
    /// @param pcvDeposit the deposit to pull funds from
    /// @param token the address of the token to withdraw
    /// @param amount the amount of funds to withdraw
    function withdrawERC20ToSafeAddress(
        address pcvDeposit,
        address token,
        uint256 amount
    ) external;

    /// @notice governor-or-guardian-or-pcv-guard method to withdraw all of an ERC20 balance from a pcv deposit, by calling the withdrawERC20() method on it
    /// @param pcvDeposit the deposit to pull funds from
    /// @param token the address of the token to withdraw
    function withdrawAllERC20ToSafeAddress(address pcvDeposit, address token)
        external;
}
