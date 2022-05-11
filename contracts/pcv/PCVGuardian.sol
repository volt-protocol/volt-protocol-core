// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CoreRef} from "../refs/CoreRef.sol";
import {IPCVGuardian} from "./IPCVGuardian.sol";
import {IPCVDeposit} from "./IPCVDeposit.sol";
import {CoreRefPauseableLib} from "../libs/CoreRefPauseableLib.sol";
import {TribeRoles} from "../core/TribeRoles.sol";

/// @notice PCV Guardian is a contract to safeguard protocol funds
/// by being able to withdraw whitelisted PCV deposits to an immutable safe address
contract PCVGuardian is IPCVGuardian, CoreRef {
    using CoreRefPauseableLib for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    ///@notice set of whitelisted pcvDeposit addresses for withdrawal
    EnumerableSet.AddressSet private whitelistAddresses;

    ///@notice safe address where PCV funds can be withdrawn to
    address public immutable safeAddress;

    constructor(
        address _core,
        address _safeAddress,
        address[] memory _whitelistAddresses
    ) CoreRef(_core) {
        safeAddress = _safeAddress;

        // improbable to ever overflow
        unchecked {
            for (uint256 i = 0; i < _whitelistAddresses.length; i++) {
                _addWhitelistAddress(_whitelistAddresses[i]);
            }
        }
    }

    /// @dev checks if a pcv deposit address is whitelisted, reverts if not
    modifier onlyWhitelist(address pcvDeposit) {
        require(
            isWhitelistAddress(pcvDeposit),
            "PCVGuardian: Provided address is not whitelisted"
        );
        _;
    }

    // ---------- Read-Only API ----------

    /// @notice returns true if the the provided address is a valid destination to withdraw funds from
    /// @param pcvDeposit the pcvDeposit address to check if whitelisted
    function isWhitelistAddress(address pcvDeposit)
        public
        view
        override
        returns (bool)
    {
        return whitelistAddresses.contains(pcvDeposit);
    }

    /// @notice returns all whitelisted pcvDeposit addresses
    function getWhitelistAddresses()
        public
        view
        override
        returns (address[] memory)
    {
        return whitelistAddresses.values();
    }

    // ---------- Governor-Only State-Changing API ----------

    /// @notice governor-only method to whitelist a pcvDeposit address to withdraw funds from
    /// @param pcvDeposit the address to whitelist
    function addWhitelistAddress(address pcvDeposit)
        external
        override
        onlyGovernor
    {
        _addWhitelistAddress(pcvDeposit);
    }

    /// @notice batch version of addWhiteListaddress
    /// @param _whitelistAddresses the addresses to whitelist, as calldata
    function addWhitelistAddresses(address[] calldata _whitelistAddresses)
        external
        override
        onlyGovernor
    {
        // improbable to ever overflow
        unchecked {
            require(
                _whitelistAddresses.length != 0,
                "PCVGuardian: Empty address array provided"
            );
            for (uint256 i = 0; i < _whitelistAddresses.length; i++) {
                _addWhitelistAddress(_whitelistAddresses[i]);
            }
        }
    }

    // ---------- Governor-Or-Guardian-Only State-Changing API ----------

    /// @notice governor-or-guardian-only method to remove pcvDeposit address from the whitelist to withdraw funds from
    /// @param pcvDeposit the address to remove from whitelist
    function removeWhitelistAddress(address pcvDeposit)
        external
        override
        onlyGuardianOrGovernor
    {
        _removeWhitelistAddress(pcvDeposit);
    }

    /// @notice batch version of removeWhitelistAddress
    /// @param _whitelistAddresses the addresses to remove from whitelist
    function removeWhitelistAddresses(address[] calldata _whitelistAddresses)
        external
        override
        onlyGuardianOrGovernor
    {
        // improbable to ever overflow
        unchecked {
            require(
                _whitelistAddresses.length != 0,
                "PCVGuardian: Empty address array provided"
            );
            for (uint256 i = 0; i < _whitelistAddresses.length; i++) {
                _removeWhitelistAddress(_whitelistAddresses[i]);
            }
        }
    }

    /// @notice governor-or-guardian-or-pcv-guard method to withdraw funds from a pcv deposit, by calling the withdraw() method on it
    /// @param pcvDeposit the address of the pcv deposit contract
    /// @param amount the amount to withdraw
    function withdrawToSafeAddress(address pcvDeposit, uint256 amount)
        external
        override
        hasAnyOfThreeRoles(
            TribeRoles.GOVERNOR,
            TribeRoles.GUARDIAN,
            TribeRoles.PCV_GUARD
        )
        onlyWhitelist(pcvDeposit)
    {
        _withdrawToSafeAddress(pcvDeposit, amount);
    }

    /// @notice governor-or-guardian-or-pcv-guard method to withdraw all at once funds from a pcv deposit, by calling the withdraw() method on it
    /// @param pcvDeposit the address of the pcv deposit contract
    function withdrawAllToSafeAddress(address pcvDeposit)
        external
        override
        hasAnyOfThreeRoles(
            TribeRoles.GOVERNOR,
            TribeRoles.GUARDIAN,
            TribeRoles.PCV_GUARD
        )
        onlyWhitelist(pcvDeposit)
    {
        _withdrawToSafeAddress(pcvDeposit, IPCVDeposit(pcvDeposit).balance());
    }

    /// @notice governor-or-guardian-only method to withdraw an ERC20 from a pcv deposit, by calling the withdrawERC20() method on it
    /// @param pcvDeposit the deposit to pull funds from
    /// @param token the address of the token to withdraw
    /// @param amount the amount of funds to withdraw
    function withdrawERC20ToSafeAddress(
        address pcvDeposit,
        address token,
        uint256 amount
    )
        external
        override
        hasAnyOfThreeRoles(
            TribeRoles.GOVERNOR,
            TribeRoles.GUARDIAN,
            TribeRoles.PCV_GUARD
        )
        onlyWhitelist(pcvDeposit)
    {
        _wtihdrawERC20ToSafeAddress(pcvDeposit, token, amount);
    }

    /// @notice governor-or-guardian-only method to withdraw all of an ERC20 balance from a pcv deposit, by calling the withdrawERC20() method on it
    /// @param pcvDeposit the deposit to pull funds from
    /// @param token the address of the token to withdraw
    function withdrawAllERC20ToSafeAddress(address pcvDeposit, address token)
        external
        override
        hasAnyOfThreeRoles(
            TribeRoles.GOVERNOR,
            TribeRoles.GUARDIAN,
            TribeRoles.PCV_GUARD
        )
        onlyWhitelist(pcvDeposit)
    {
        _wtihdrawERC20ToSafeAddress(
            pcvDeposit,
            token,
            IERC20(token).balanceOf(pcvDeposit)
        );
    }

    // ---------- Internal Functions ----------

    function _withdrawToSafeAddress(address pcvDeposit, uint256 amount)
        internal
    {
        if (pcvDeposit._paused()) {
            pcvDeposit._unpause();
            IPCVDeposit(pcvDeposit).withdraw(safeAddress, amount);
            pcvDeposit._pause();
        } else {
            IPCVDeposit(pcvDeposit).withdraw(safeAddress, amount);
        }

        emit PCVGuardianWithdrawal(pcvDeposit, amount);
    }

    function _wtihdrawERC20ToSafeAddress(
        address pcvDeposit,
        address token,
        uint256 amount
    ) internal {
        IPCVDeposit(pcvDeposit).withdrawERC20(token, safeAddress, amount);
        emit PCVGuardianERC20Withdrawal(pcvDeposit, token, amount);
    }

    function _addWhitelistAddress(address pcvDeposit) internal {
        require(
            whitelistAddresses.add(pcvDeposit),
            "PCVGuardian: Failed to add address to whitelist"
        );
        emit WhitelistAddressAdded(pcvDeposit);
    }

    function _removeWhitelistAddress(address pcvDeposit) internal {
        require(
            whitelistAddresses.remove(pcvDeposit),
            "PCVGuardian: Failed to remove address from whitelist"
        );
        emit WhitelistAddressRemoved(pcvDeposit);
    }
}
