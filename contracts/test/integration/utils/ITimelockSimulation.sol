pragma solidity =0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IPCVGuardian} from "../../../pcv/IPCVGuardian.sol";
import {Vm} from "./../../unit/utils/Vm.sol";

interface ITimelockSimulation {
    /// an array of actions makes up a proposal
    struct action {
        address target;
        uint256 value;
        bytes arguments;
        string description;
    }

    /// @notice simulate timelock proposal
    /// @param proposal an array of actions that compose a proposal
    /// @param timelock to execute the proposal against
    /// @param guardian to verify all transfers are authorized to hold PCV
    /// @param executor account to execute the proposal on the timelock
    /// @param proposer account to propose the proposal to the timelock
    /// @param vm reference to a foundry vm instance
    /// @param doLogging toggle to print out calldata and steps
    function simulate(
        action[] memory proposal,
        TimelockController timelock,
        IPCVGuardian guardian,
        address executor,
        address proposer,
        Vm vm,
        bool doLogging
    ) external;
}
