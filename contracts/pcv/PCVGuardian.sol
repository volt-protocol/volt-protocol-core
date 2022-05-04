// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {CoreRef} from "../refs/CoreRef.sol";
import {IPCVGuardian} from "./IPCVGuardian.sol";
import {IPCVDeposit} from "./IPCVDeposit.sol";
import {CoreRefPauseableLib} from "../libs/CoreRefPauseableLib.sol";

contract PCVGuardian is IPCVGuardian, CoreRef {
    using CoreRefPauseableLib for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private whitelistAddresses;

    address public immutable safeAddress;

    constructor(
        address _core,
        address _safeAddress,
        address[] memory _whitelistAddresses
    ) CoreRef(_core) {
        safeAddress = _safeAddress;

        for (uint256 i = 0; i < _whitelistAddresses.length; i++) {
            _setWhitelistAddress(_whitelistAddresses[i]);
        }
    }

    // ---------- Read-Only API ----------

    /// @notice returns true if the the provided address is a valid destination to withdraw funds to
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

    /// @notice governor-only method to set an address as "safe" to withdraw funds to
    /// @param pcvDeposit the address to set as safe
    function setWhitelistAddress(address pcvDeposit)
        external
        override
        onlyGovernor
    {
        _setWhitelistAddress(pcvDeposit);
    }

    /// @notice batch version of setSafeAddress
    /// @param _whitelistAddresses the addresses to set as safe, as calldata
    function setWhitelistAddresses(address[] calldata _whitelistAddresses)
        external
        override
        onlyGovernor
    {
        require(_whitelistAddresses.length != 0, "empty");
        for (uint256 i = 0; i < _whitelistAddresses.length; i++) {
            _setWhitelistAddress(_whitelistAddresses[i]);
        }
    }

    // ---------- Governor-Or-Guardian-Only State-Changing API ----------

    /// @notice governor-or-guardian-only method to un-set an address as "safe" to withdraw funds to
    /// @param pcvDeposit the address to un-set as safe
    function unsetWhitelistAddress(address pcvDeposit)
        external
        override
        onlyGuardianOrGovernor
    {
        _unsetWhitelistAddress(pcvDeposit);
    }

    /// @notice batch version of unsetSafeAddresses
    /// @param _whitelistAddresses the addresses to un-set as safe
    function unsetWhitelistAddresses(address[] calldata _whitelistAddresses)
        external
        override
        onlyGuardianOrGovernor
    {
        require(_whitelistAddresses.length != 0, "empty");
        for (uint256 i = 0; i < _whitelistAddresses.length; i++) {
            _unsetWhitelistAddress(_whitelistAddresses[i]);
        }
    }

    /// @notice governor-or-guardian-only method to withdraw funds from a pcv deposit, by calling the withdraw() method on it
    /// @param pcvDeposit the address of the pcv deposit contract
    /// @param amount the amount to withdraw
    /// @param pauseAfter if true, the pcv contract will be paused after the withdraw
    function withdrawToSafeAddress(
        address pcvDeposit,
        uint256 amount,
        bool pauseAfter
    ) external override onlyGuardianOrGovernor {
        require(
            isWhitelistAddress(pcvDeposit),
            "Provided address is not whitelisted"
        );

        pcvDeposit._ensureUnpaused();

        IPCVDeposit(pcvDeposit).withdraw(safeAddress, amount);

        if (pauseAfter) {
            pcvDeposit._pause();
        }

        emit PCVGuardianWithdrawal(pcvDeposit, safeAddress, amount);
    }

    // ---------- Internal Functions ----------

    function _setWhitelistAddress(address anAddress) internal {
        require(whitelistAddresses.add(anAddress), "set");
        emit SafeAddressAdded(anAddress);
    }

    function _unsetWhitelistAddress(address anAddress) internal {
        require(whitelistAddresses.remove(anAddress), "unset");
        emit SafeAddressRemoved(anAddress);
    }
}
