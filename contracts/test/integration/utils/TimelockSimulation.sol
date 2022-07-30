pragma solidity =0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {DSTest} from "./../../unit/utils/DSTest.sol";
import {Vm} from "./../../unit/utils/Vm.sol";

import "hardhat/console.sol";

contract TimelockSimulation is DSTest {
    /// an array of actions makes up a proposal
    struct action {
        address target;
        uint256 value;
        bytes arguments;
        string description;
    }

    function simulate(
        action[] memory proposal,
        TimelockController timelock,
        address executor,
        address proposer,
        Vm vm
    ) public {
        uint256 delay = timelock.getMinDelay();
        bytes32 salt = keccak256(abi.encode(proposal[0].description));
        console.log("salt: ");
        emit log_bytes32(salt);

        bytes32 predecessor = bytes32(0);

        uint256 proposalLength = proposal.length;
        address[] memory targets = new address[](proposalLength);
        uint256[] memory values = new uint256[](proposalLength);
        bytes[] memory payloads = new bytes[](proposalLength);

        /// target cannot be address 0 as that call will fail
        /// value can be 0
        /// arguments can be 0 as long as eth is sent
        for (uint256 i = 0; i < proposalLength; i++) {
            require(
                proposal[i].target != address(0),
                "Invalid target for timelock"
            );
            /// if there are no args and no eth, the action is not valid
            require(
                (proposal[i].arguments.length == 0 && proposal[i].value > 0) ||
                    proposal[i].arguments.length > 0,
                "Invalid arguments for timelock"
            );

            targets[i] = proposal[i].target;
            values[i] = proposal[i].value;
            payloads[i] = proposal[i].arguments;
        }

        bytes32 proposalId = timelock.hashOperationBatch(
            targets,
            values,
            payloads,
            predecessor,
            salt
        );

        if (!timelock.isOperationPending(proposalId)) {
            vm.prank(proposer);
            timelock.scheduleBatch(
                targets,
                values,
                payloads,
                predecessor,
                salt,
                delay
            );
            console.log("schedule batch calldata");
            emit log_bytes(
                abi.encodeWithSignature(
                    "scheduleBatch(address[],uint256[],bytes[],bytes32,bytes32,uint256)",
                    targets,
                    values,
                    payloads,
                    predecessor,
                    salt,
                    delay
                )
            );
        } else {
            console.log("proposal already scheduled for id");
            emit log_bytes32(proposalId);
        }

        vm.warp(block.timestamp + delay);

        if (!timelock.isOperationDone(proposalId)) {
            vm.prank(executor);
            timelock.executeBatch(targets, values, payloads, predecessor, salt);

            console.log("execute batch calldata");
            emit log_bytes(
                abi.encodeWithSignature(
                    "executeBatch(address[],uint256[],bytes[],bytes32,bytes32)",
                    targets,
                    values,
                    payloads,
                    predecessor,
                    salt
                )
            );
        } else {
            console.log("proposal already executed");
        }
    }
}
