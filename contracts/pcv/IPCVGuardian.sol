// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

/// @title IPCVGuardian
/// @notice an interface for defining how the PCVGuardian functions
/// @dev any implementation of this contract should be granted the roles of Guardian and PCVController in order to work correctly
interface IPCVGuardian {
    // ---------- Events ----------
    event SafeAddressAdded(address indexed safeAddress);

    event SafeAddressRemoved(address indexed safeAddress);

    event PCVGuardianWithdrawal(
        address indexed pcvDeposit,
        address indexed destination,
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

    /// @notice governor-only method to whitelist an address as part of the internal addresses that can be withdrawn from
    /// @param pcvDeposit to add to whitelisted addresses
    function setWhitelistAddress(address pcvDeposit) external;

    /// @notice batch version of setWhitelistAddress
    /// @param whitelistAddresses the addresses to set as safe, as calldata
    function setWhitelistAddresses(address[] calldata whitelistAddresses)
        external;

    // ---------- Governor-or-Guardian-Only State-Changing API ----------

    /// @notice governor-or-guardian-only method to un-whitelist an address as part of the internal addresses that can be withdrawn from
    /// @param pcvDeposit the address to un-set as safe
    function unsetWhitelistAddress(address pcvDeposit) external;

    /// @notice batch version of unsetWhitelistAddress
    /// @param whitelistAddresses the addresses to un-set as safe
    function unsetWhitelistAddresses(address[] calldata whitelistAddresses)
        external;

    /// @notice governor-or-guardian-only method to withdraw funds from a pcv deposit, by calling the withdraw() method on it
    /// @param pcvDeposit the address of the pcv deposit contract
    /// @param amount the amount to withdraw
    /// @param pauseAfter if true, the pcv contract will be paused after the withdraw
    function withdrawToSafeAddress(
        address pcvDeposit,
        uint256 amount,
        bool pauseAfter
    ) external;
}
