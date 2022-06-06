// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Vm} from "../unit/utils/Vm.sol";
import {ICore} from "../../core/ICore.sol";
import {DSTest} from "../unit/utils/DSTest.sol";
import {PSMRouter} from "./../../peg/PSMRouter.sol";
import {OptimisticTimelock} from "./../../dao/OptimisticTimelock.sol";
import {INonCustodialPSM} from "./../../peg/NonCustodialPSM.sol";
import {IVolt, Volt} from "../../volt/Volt.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {getCore, getAddresses, getVoltAddresses, FeiTestAddresses, VoltAddresses} from "../unit/utils/Fixtures.sol";

contract IntegrationTestOATimelock is DSTest {
    Vm public constant vm = Vm(HEVM_ADDRESS);
    ICore public core = ICore(0xEC7AD284f7Ad256b64c6E69b84Eb0F48f42e8196);
    OptimisticTimelock public oaTimelock;
    FeiTestAddresses public addresses = getAddresses();
    VoltAddresses public voltAddresses = getVoltAddresses();
    address public proposer1 = voltAddresses.pcvGuardAddress1;
    address public proposer2 = voltAddresses.pcvGuardAddress2;
    address public executorAddress = voltAddresses.executorAddress;

    function setUp() public {
        address[] memory proposerCancellerAddresses = new address[](2);
        proposerCancellerAddresses[0] = proposer1;
        proposerCancellerAddresses[1] = proposer2;

        address[] memory executorAddresses = new address[](1);
        executorAddresses[0] = voltAddresses.executorAddress;

        oaTimelock = new OptimisticTimelock(
            address(core),
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

        assertTrue(
            oaTimelock.hasRole(oaTimelock.EXECUTOR_ROLE(), executorAddress)
        );
    }

    function testTimelockEthReceive() public {
        assertEq(address(oaTimelock).balance, 0); // starts with 0 balance

        uint256 ethSendAmount = 100 ether;
        vm.deal(proposer1, ethSendAmount);

        vm.prank(proposer1);
        (bool success, ) = address(oaTimelock).call{value: ethSendAmount}("");

        assertTrue(success);
        assertEq(address(oaTimelock).balance, ethSendAmount);
    }

    function testTimelockSendEth() public {
        uint256 ethSendAmount = 100 ether;
        vm.deal(address(oaTimelock), ethSendAmount);

        assertEq(address(oaTimelock).balance, ethSendAmount); // starts with 0 balance

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

        assertTrue(!oaTimelock.isOperationDone(id)); // operation is not done
        assertTrue(!oaTimelock.isOperationReady(id)); // operation is not ready

        vm.warp(block.timestamp + 600);
        assertTrue(oaTimelock.isOperationReady(id)); // operation is ready

        vm.prank(executorAddress);
        oaTimelock.execute(proposer1, ethSendAmount, data, predecessor, salt);

        assertTrue(oaTimelock.isOperationDone(id)); // operation is done

        assertEq(address(oaTimelock).balance, 0);
        assertEq(proposer1.balance, ethSendAmount + startingProposerEthBalance); /// assert proposer received their eth
    }
}
