// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
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
                _setWhitelistAddress(_whitelistAddresses[i]);
            }
        }
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

    /// @notice governor-only method to whitelist a pcvDesposit address to withdraw funds from
    /// @param pcvDeposit the address to set as safe
    function setWhitelistAddress(address pcvDeposit)
        external
        override
        onlyGovernor
    {
        _setWhitelistAddress(pcvDeposit);
    }

    /// @notice batch version of setWhiteListaddress
    /// @param _whitelistAddresses the addresses to whitelist, as calldata
    function setWhitelistAddresses(address[] calldata _whitelistAddresses)
        external
        override
        onlyGovernor
    {
        // improbable to ever overflow
        unchecked {
            require(_whitelistAddresses.length != 0, "empty");
            for (uint256 i = 0; i < _whitelistAddresses.length; i++) {
                _setWhitelistAddress(_whitelistAddresses[i]);
            }
        }
    }

    // ---------- Governor-Or-Guardian-Only State-Changing API ----------

    /// @notice governor-or-guardian-only method to un-whitelist a pcvDesposit address to withdraw funds from
    /// @param pcvDeposit the address to un-set as safe
    function unsetWhitelistAddress(address pcvDeposit)
        external
        override
        onlyGuardianOrGovernor
    {
        _unsetWhitelistAddress(pcvDeposit);
    }

    /// @notice batch version of unsetWhitelistAddress
    /// @param _whitelistAddresses the addresses to un-whitelist
    function unsetWhitelistAddresses(address[] calldata _whitelistAddresses)
        external
        override
        onlyGuardianOrGovernor
    {
        // improbable to ever overflow
        unchecked {
            require(_whitelistAddresses.length != 0, "empty");
            for (uint256 i = 0; i < _whitelistAddresses.length; i++) {
                _unsetWhitelistAddress(_whitelistAddresses[i]);
            }
        }
    }

    /// @notice governor-or-guardian-pcv-guard method to withdraw funds from a pcv deposit, by calling the withdraw() method on it
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
    {
        require(
            isWhitelistAddress(pcvDeposit),
            "Provided address is not whitelisted"
        );

        if (pcvDeposit._paused()) {
            pcvDeposit._unpause();
            IPCVDeposit(pcvDeposit).withdraw(safeAddress, amount);
            pcvDeposit._pause();
        } else {
            IPCVDeposit(pcvDeposit).withdraw(safeAddress, amount);
        }

        emit PCVGuardianWithdrawal(pcvDeposit, amount);
    }

    // ---------- Internal Functions ----------

    function _setWhitelistAddress(address pcvDeposit) internal {
        require(whitelistAddresses.add(pcvDeposit), "set");
        emit WhitelistAddressAdded(pcvDeposit);
    }

    function _unsetWhitelistAddress(address pcvDeposit) internal {
        require(whitelistAddresses.remove(pcvDeposit), "unset");
        emit WhitelistAddressRemoved(pcvDeposit);
    }
}
