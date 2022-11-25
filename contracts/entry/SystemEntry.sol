// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {IPCVOracle} from "../oracle/IPCVOracle.sol";
import {IPCVDepositV2} from "../pcv/IPCVDepositV2.sol";

/// @notice contract to accrue, deposit or harvest
/// on PCV deposit contracts.
contract SystemEntry is CoreRefV2 {
    constructor(address _core) CoreRefV2(_core) {}

    /// @notice Enforce that the PCV Deposit we call
    /// .accrue(), .deposit(), or .harvest()
    /// on is a valid PCV Deposit added in the oracle.
    /// This protects from giving the execution flow to an arbitrary
    /// contract whose address is passed as calldata while the system
    /// is in a locked state level 1.
    modifier onlyValidDeposit(address pcvDeposit) {
        IPCVOracle _pcvOracle = pcvOracle();
        if (address(_pcvOracle) != address(0)) {
            bool isVenue = _pcvOracle.isVenue(pcvDeposit);
            require(isVenue, "SystemEntry: Invalid PCVDeposit");
        }
        _;
    }

    /// @notice lock the system to level 1, then call accrue
    /// @param pcvDeposit to call accrue
    /// @return the balance of the PCV Deposit being called
    function accrue(
        address pcvDeposit
    )
        external
        whenNotPaused
        globalLock(1)
        onlyValidDeposit(pcvDeposit)
        returns (uint256)
    {
        return IPCVDepositV2(pcvDeposit).accrue();
    }

    /// @notice lock the system to level 1, then call deposit
    /// @param pcvDeposit to call deposit
    function deposit(
        address pcvDeposit
    ) external whenNotPaused globalLock(1) onlyValidDeposit(pcvDeposit) {
        IPCVDepositV2(pcvDeposit).deposit();
    }

    /// @notice lock the system to level 1, then call harvest
    /// @param pcvDeposit to call harvest
    function harvest(
        address pcvDeposit
    ) external whenNotPaused globalLock(1) onlyValidDeposit(pcvDeposit) {
        IPCVDepositV2(pcvDeposit).harvest();
    }
}
