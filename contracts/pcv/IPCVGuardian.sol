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

    /// @notice governor-only method to whitelist an address as part of the internal addresses that can be withdrawn from
    /// @param pcvDeposit to add to whitelisted addresses
    function setWhitelistAddress(address pcvDeposit) external;

    /// @notice batch version of setWhitelistAddress
    /// @param whitelistAddresses the pcvDespoit addresses to whitelist, as calldata
    function setWhitelistAddresses(address[] calldata whitelistAddresses)
        external;

    // ---------- Governor-or-Guardian-Only State-Changing API ----------

    /// @notice governor-or-guardian-only method to un-whitelist an address as part of the internal addresses that can be withdrawn from
    /// @param pcvDeposit the address to un-whitelist
    function unsetWhitelistAddress(address pcvDeposit) external;

    /// @notice batch version of unsetWhitelistAddress
    /// @param whitelistAddresses the addresses to un-whitelist
    function unsetWhitelistAddresses(address[] calldata whitelistAddresses)
        external;

    /// @notice governor-or-guardian-or-pcv-guard method to withdraw funds from a pcv deposit, by calling the withdraw() method on it
    /// @param pcvDeposit the address of the pcv deposit contract
    /// @param amount the amount to withdraw
    function withdrawToSafeAddress(address pcvDeposit, uint256 amount) external;

    /// @notice governor-or-guardian-or-pcv-guard method to withdraw all at once funds from a pcv deposit, by calling the withdraw() method on it
    /// @param pcvDeposit the address of the pcv deposit contract
    function withdrawAllToSafeAddress(address pcvDeposit) external;
}
