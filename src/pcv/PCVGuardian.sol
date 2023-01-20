// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CoreRefV2} from "@voltprotocol/refs/CoreRefV2.sol";
import {VoltRoles} from "@voltprotocol/core/VoltRoles.sol";
import {IPCVDeposit} from "@voltprotocol/pcv/IPCVDeposit.sol";
import {IPCVGuardian} from "@voltprotocol/pcv/IPCVGuardian.sol";

/// @notice PCV Guardian is a contract to safeguard protocol funds
/// by being able to withdraw whitelisted PCV deposits to a safe address
contract PCVGuardian is IPCVGuardian, CoreRefV2 {
    using EnumerableSet for EnumerableSet.AddressSet;

    ///@notice set of whitelisted pcvDeposit addresses for withdrawal
    EnumerableSet.AddressSet private whitelistAddresses;

    ///@notice safe address where PCV funds can be withdrawn to
    address public safeAddress;

    constructor(
        address _core,
        address _safeAddress,
        address[] memory _whitelistAddresses
    ) CoreRefV2(_core) {
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
    function isWhitelistAddress(
        address pcvDeposit
    ) public view override returns (bool) {
        return whitelistAddresses.contains(pcvDeposit);
    }

    /// @notice returns all whitelisted pcvDeposit addresses
    function getWhitelistAddresses()
        external
        view
        override
        returns (address[] memory)
    {
        return whitelistAddresses.values();
    }

    // ---------- Governor-Only State-Changing API ----------

    /// @notice governor-only method to change the safe address
    /// @param newSafeAddress new safe address
    function setSafeAddress(
        address newSafeAddress
    ) external override onlyGovernor {
        address oldSafeAddress = safeAddress;

        safeAddress = newSafeAddress;

        emit SafeAddressUpdated(oldSafeAddress, newSafeAddress);
    }

    /// @notice governor-only method to whitelist a pcvDeposit address to withdraw funds from
    /// @param pcvDeposit the address to whitelist
    function addWhitelistAddress(
        address pcvDeposit
    ) external override onlyGovernor {
        _addWhitelistAddress(pcvDeposit);
    }

    /// @notice batch version of addWhiteListaddress
    /// @param _whitelistAddresses the addresses to whitelist, as calldata
    function addWhitelistAddresses(
        address[] calldata _whitelistAddresses
    ) external override onlyGovernor {
        // improbable to ever overflow
        unchecked {
            for (uint256 i = 0; i < _whitelistAddresses.length; i++) {
                _addWhitelistAddress(_whitelistAddresses[i]);
            }
        }
    }

    // ---------- Governor-Or-Guardian-Only State-Changing API ----------

    /// @notice governor-or-guardian-only method to remove pcvDeposit address from the whitelist to withdraw funds from
    /// @param pcvDeposit the address to remove from whitelist
    function removeWhitelistAddress(
        address pcvDeposit
    ) external override onlyGuardianOrGovernor {
        _removeWhitelistAddress(pcvDeposit);
    }

    /// @notice batch version of removeWhitelistAddress
    /// @param _whitelistAddresses the addresses to remove from whitelist
    function removeWhitelistAddresses(
        address[] calldata _whitelistAddresses
    ) external override onlyGuardianOrGovernor {
        // improbable to ever overflow
        unchecked {
            for (uint256 i = 0; i < _whitelistAddresses.length; i++) {
                _removeWhitelistAddress(_whitelistAddresses[i]);
            }
        }
    }

    // ---------- PCV Guardian State-Changing API ----------

    // -----------------------------------------------------
    // -------------------  WARNING!!! ---------------------
    // -----------------------------------------------------
    //   USING THESE FUNCTIONS WILL MAKE THE PCVORACLE THINK
    //   THAT ASSETS FLOWED OUT OF THE SYSTEM, BECAUSE TOKEN
    //   BALANCES ON THE SAFE ADDRESS (DAO TIMELOCK) ARE NOT
    //   COUNTED AS PART OF PCV. ONLY USE FUNCTIONS IN AN
    //   EMERGENCY SITUATION IF WITHDRAWING FROM PCV DEPOSITS.
    // -----------------------------------------------------
    //   WITHDRAWING FROM A PSM WILL NOT HAVE THE SAME
    //   EFFECT BECAUSE ASSETS IN PSM ARE ALREADY COUNTED
    //   OUT OF THE SYSTEM FROM AN ACCOUNTING PERSPECTIVE.
    // -----------------------------------------------------
    // -----------------------------------------------------

    /// @notice governor-or-guardian-or-pcv-guard method to withdraw funds from a pcv deposit, by calling the withdraw() method on it
    /// @param pcvDeposit the address of the pcv deposit contract
    /// @param amount the amount to withdraw
    function withdrawToSafeAddress(
        address pcvDeposit,
        uint256 amount
    )
        external
        override
        hasAnyOfThreeRoles(
            VoltRoles.GOVERNOR,
            VoltRoles.GUARDIAN,
            VoltRoles.PCV_GUARD
        )
        globalLock(1)
        onlyWhitelist(pcvDeposit)
    {
        _withdrawToSafeAddress(pcvDeposit, amount);
    }

    /// @notice governor-or-guardian-or-pcv-guard method to withdraw all at once funds from a pcv deposit, by calling the withdraw() method on it
    /// @param pcvDeposit the address of the pcv deposit contract
    function withdrawAllToSafeAddress(
        address pcvDeposit
    )
        external
        override
        hasAnyOfThreeRoles(
            VoltRoles.GOVERNOR,
            VoltRoles.GUARDIAN,
            VoltRoles.PCV_GUARD
        )
        globalLock(1)
        onlyWhitelist(pcvDeposit)
    {
        _withdrawToSafeAddress(pcvDeposit, IPCVDeposit(pcvDeposit).balance());
    }

    /// @notice governor-or-guardian-or-pcv-guard method to withdraw an ERC20 from a pcv deposit, by calling the withdrawERC20() method on it
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
            VoltRoles.GOVERNOR,
            VoltRoles.GUARDIAN,
            VoltRoles.PCV_GUARD
        )
        globalLock(1)
        onlyWhitelist(pcvDeposit)
    {
        _withdrawERC20ToSafeAddress(pcvDeposit, token, amount);
    }

    /// @notice governor-or-guardian-or-pcv-guard method to withdraw all of an ERC20 balance from a pcv deposit, by calling the withdrawERC20() method on it
    /// @param pcvDeposit the deposit to pull funds from
    /// @param token the address of the token to withdraw
    function withdrawAllERC20ToSafeAddress(
        address pcvDeposit,
        address token
    )
        external
        override
        hasAnyOfThreeRoles(
            VoltRoles.GOVERNOR,
            VoltRoles.GUARDIAN,
            VoltRoles.PCV_GUARD
        )
        globalLock(1)
        onlyWhitelist(pcvDeposit)
    {
        _withdrawERC20ToSafeAddress(
            pcvDeposit,
            token,
            IERC20(token).balanceOf(pcvDeposit)
        );
    }

    // ---------- Private Functions ----------

    function _withdrawToSafeAddress(
        address pcvDeposit,
        uint256 amount
    ) private {
        if (CoreRefV2(pcvDeposit).paused()) {
            CoreRefV2(pcvDeposit).unpause();
            IPCVDeposit(pcvDeposit).withdraw(safeAddress, amount);
            CoreRefV2(pcvDeposit).pause();
        } else {
            IPCVDeposit(pcvDeposit).withdraw(safeAddress, amount);
        }

        emit PCVGuardianWithdrawal(pcvDeposit, amount);
    }

    function _withdrawERC20ToSafeAddress(
        address pcvDeposit,
        address token,
        uint256 amount
    ) private {
        IPCVDeposit(pcvDeposit).withdrawERC20(token, safeAddress, amount);
        emit PCVGuardianERC20Withdrawal(pcvDeposit, token, amount);
    }

    function _addWhitelistAddress(address pcvDeposit) private {
        require(
            whitelistAddresses.add(pcvDeposit),
            "PCVGuardian: Failed to add address to whitelist"
        );
        emit WhitelistAddressAdded(pcvDeposit);
    }

    function _removeWhitelistAddress(address pcvDeposit) private {
        require(
            whitelistAddresses.remove(pcvDeposit),
            "PCVGuardian: Failed to remove address from whitelist"
        );
        emit WhitelistAddressRemoved(pcvDeposit);
    }
}