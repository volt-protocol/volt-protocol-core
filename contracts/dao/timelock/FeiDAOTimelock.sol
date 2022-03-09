// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./Timelock.sol";
import "../../refs/CoreRef.sol";

/** 
 @title Fei DAO Timelock
 @notice Timelock with veto admin roles
 @dev this timelock has the ability for the Guardian to pause queing or executing proposals, as well as being able to veto specific transactions. 
 The timelock itself could not unpause the timelock while in paused state.
*/
contract FeiDAOTimelock is Timelock, CoreRef {
    constructor(
        address core_,
        address admin_,
        uint256 delay_,
        uint256 minDelay_
    ) Timelock(admin_, delay_, minDelay_) CoreRef(core_) {}

    /// @notice queue a transaction, with pausability
    function queueTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) public override whenNotPaused returns (bytes32) {
        return super.queueTransaction(target, value, signature, data, eta);
    }

    /// @notice veto a group of transactions
    function vetoTransactions(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory datas,
        uint256[] memory etas
    ) public onlyGuardianOrGovernor {
        for (uint256 i = 0; i < targets.length; i++) {
            _cancelTransaction(
                targets[i],
                values[i],
                signatures[i],
                datas[i],
                etas[i]
            );
        }
    }

    /// @notice execute a transaction, with pausability
    function executeTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) public payable override whenNotPaused returns (bytes memory) {
        return super.executeTransaction(target, value, signature, data, eta);
    }

    /// @notice allow a governor to set a new pending timelock admin
    function governorSetPendingAdmin(address newAdmin) public onlyGovernor {
        pendingAdmin = newAdmin;
        emit NewPendingAdmin(newAdmin);
    }
}
