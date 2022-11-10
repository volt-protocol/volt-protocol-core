// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Vm} from "../unit/utils/Vm.sol";
import {ICore} from "../../core/ICore.sol";
import {DSTest} from "../unit/utils/DSTest.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVolt, Volt} from "../../volt/Volt.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";

contract IntegrationTestTimelockController is DSTest {
    Vm public constant vm = Vm(HEVM_ADDRESS);
    TimelockController public oaTimelock;
    address public proposer1 = MainnetAddresses.REVOKED_EOA_1;
    address public proposer2 = MainnetAddresses.EOA_2;
    address public executorAddress = MainnetAddresses.GOVERNOR;

    function setUp() public {
        address[] memory proposerCancellerAddresses = new address[](3);
        proposerCancellerAddresses[0] = proposer1;
        proposerCancellerAddresses[1] = proposer2;
        proposerCancellerAddresses[2] = executorAddress;

        address[] memory executorAddresses = new address[](1);
        executorAddresses[0] = MainnetAddresses.GOVERNOR;

        oaTimelock = new TimelockController(
            600,
            proposerCancellerAddresses,
            executorAddresses
        );
    }

    function testSetup() public {
        assertTrue(oaTimelock.hasRole(oaTimelock.CANCELLER_ROLE(), proposer1));
        assertTrue(oaTimelock.hasRole(oaTimelock.PROPOSER_ROLE(), proposer1));

        assertTrue(oaTimelock.hasRole(oaTimelock.CANCELLER_ROLE(), proposer2));
        assertTrue(oaTimelock.hasRole(oaTimelock.PROPOSER_ROLE(), proposer2));

        /// ensure multisig has PROPOSER, CANCELLER and EXECUTOR roles
        assertTrue(
            oaTimelock.hasRole(oaTimelock.CANCELLER_ROLE(), executorAddress)
        );
        assertTrue(
            oaTimelock.hasRole(oaTimelock.PROPOSER_ROLE(), executorAddress)
        );
        assertTrue(
            oaTimelock.hasRole(oaTimelock.EXECUTOR_ROLE(), executorAddress)
        );
    }

    function testTimelockEthReceive() public {
        uint256 startingOABalance = address(oaTimelock).balance;

        uint256 ethSendAmount = 100 ether;
        vm.deal(proposer1, ethSendAmount);

        vm.prank(proposer1);
        (bool success, ) = address(oaTimelock).call{value: ethSendAmount}("");

        assertTrue(success);
        assertEq(
            address(oaTimelock).balance - startingOABalance,
            ethSendAmount
        );
    }

    function testTimelockSendEth() public {
        uint256 ethSendAmount = 100 ether;
        vm.deal(address(oaTimelock), ethSendAmount);

        assertEq(address(oaTimelock).balance, ethSendAmount); /// starts with 0 balance

        bytes memory data = "";
        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(0);
        vm.prank(proposer1);
        oaTimelock.schedule(
            proposer1,
            ethSendAmount,
            data,
            predecessor,
            salt,
            600
        );
        bytes32 id = oaTimelock.hashOperation(
            proposer1,
            ethSendAmount,
            data,
            predecessor,
            salt
        );

        uint256 startingProposerEthBalance = proposer1.balance;

        assertTrue(!oaTimelock.isOperationDone(id)); /// operation is not done
        assertTrue(!oaTimelock.isOperationReady(id)); /// operation is not ready

        vm.warp(block.timestamp + 600);
        assertTrue(oaTimelock.isOperationReady(id)); /// operation is ready

        vm.prank(executorAddress);
        oaTimelock.execute(proposer1, ethSendAmount, data, predecessor, salt);

        assertTrue(oaTimelock.isOperationDone(id)); /// operation is done

        assertEq(address(oaTimelock).balance, 0);
        assertEq(proposer1.balance, ethSendAmount + startingProposerEthBalance); /// assert proposer received their eth
    }
}
