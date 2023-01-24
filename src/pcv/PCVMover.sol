// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {console} from "@forge-std/console.sol";
import {IPCVMover} from "@voltprotocol/pcv/IPCVMover.sol";
import {CoreRefV2} from "@voltprotocol/refs/CoreRefV2.sol";
import {IPCVOracle} from "@voltprotocol/oracle/IPCVOracle.sol";
import {IPCVSwapper} from "@voltprotocol/pcv/IPCVSwapper.sol";
import {IPCVDeposit} from "@voltprotocol/pcv/IPCVDeposit.sol";

abstract contract PCVMover is IPCVMover, CoreRefV2 {
    using EnumerableSet for EnumerableSet.AddressSet;

    ///@notice set of whitelisted PCV swappers
    EnumerableSet.AddressSet private pcvSwappers;

    // ---------- Read-Only API ------------------

    /// @notice returns true if the the provided address is a valid swapper to use
    /// @param pcvSwapper the pcvSwapper address to check if whitelisted
    function isPCVSwapper(
        address pcvSwapper
    ) public view override returns (bool) {
        return pcvSwappers.contains(pcvSwapper);
    }

    /// @notice returns all whitelisted PCV swappers
    function getPCVSwappers()
        external
        view
        override
        returns (address[] memory)
    {
        return pcvSwappers.values();
    }

    // ---------- PCVSwapper Management API ------

    /// @notice Add multiple PCV Swappers to the whitelist
    /// @param _pcvSwappers the addresses to whitelist, as calldata
    function addPCVSwappers(
        address[] calldata _pcvSwappers
    ) external override onlyGovernor {
        unchecked {
            for (uint256 i = 0; i < _pcvSwappers.length; i++) {
                require(
                    pcvSwappers.add(_pcvSwappers[i]),
                    "PCVRouter: Failed to add swapper"
                );
                emit PCVSwapperAdded(_pcvSwappers[i]);
            }
        }
    }

    /// @notice Remove multiple PCV Swappers from the whitelist
    /// @param _pcvSwappers the addresses to remove from whitelist, as calldata
    function removePCVSwappers(
        address[] calldata _pcvSwappers
    ) external override onlyGovernor {
        unchecked {
            for (uint256 i = 0; i < _pcvSwappers.length; i++) {
                require(
                    pcvSwappers.remove(_pcvSwappers[i]),
                    "PCVRouter: Failed to remove swapper"
                );
                emit PCVSwapperRemoved(_pcvSwappers[i]);
            }
        }
    }

    /// ------------- Helper Methods -------------
    function _movePCV(
        address source,
        address destination,
        address swapper,
        uint256 amountSource,
        address sourceAsset,
        address destinationAsset
    ) internal {
        // Do transfer
        uint256 amountDestination;
        if (swapper != address(0)) {
            IPCVDeposit(source).withdraw(swapper, amountSource);
            amountDestination = IPCVSwapper(swapper).swap(
                sourceAsset,
                destinationAsset,
                destination
            );
            console.log("Successfully swapped: ", amountDestination);
        } else {
            IPCVDeposit(source).withdraw(destination, amountSource);
            amountDestination = amountSource;
        }
        IPCVDeposit(destination).deposit();

        // Emit event
        emit PCVMovement(source, destination, amountSource, amountDestination);
    }

    function _checkPCVMove(
        address source,
        address destination,
        address swapper,
        address sourceAsset,
        address destinationAsset
    ) internal view {
        // Check both deposits are still valid for PCVOracle
        IPCVOracle _pcvOracle = pcvOracle();
        require(_pcvOracle.isVenue(source), "PCVRouter: invalid source");
        require(
            _pcvOracle.isVenue(destination),
            "PCVRouter: invalid destination"
        );

        // Check underlying tokens
        require(
            IPCVDeposit(source).balanceReportedIn() == sourceAsset,
            "PCVRouter: invalid source asset"
        );
        require(
            IPCVDeposit(destination).balanceReportedIn() == destinationAsset,
            "PCVRouter: invalid destination asset"
        );

        if (sourceAsset != destinationAsset) {
            require(swapper != address(0), "MarketGovernance: invalid swapper");
        }

        // Check swapper, if applicable
        if (swapper != address(0)) {
            require(isPCVSwapper(swapper), "PCVRouter: invalid swapper");
            require(
                IPCVSwapper(swapper).canSwap(sourceAsset, destinationAsset),
                "PCVRouter: unsupported swap"
            );
        }
    }
}
