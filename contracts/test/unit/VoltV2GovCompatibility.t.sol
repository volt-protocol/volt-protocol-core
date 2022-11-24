//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {DSTest} from "../unit/utils/DSTest.sol";
import {Vm} from "../unit/utils/Vm.sol";
import {VoltV2} from "../../volt/VoltV2.sol";
import {Core} from "../../core/Core.sol";
import {getCore, getAddresses, VoltTestAddresses} from "./utils/Fixtures.sol";
import {ICore} from "../../core/ICore.sol";
import {stdError} from "../unit/utils/StdLib.sol";
import {MockDAO, IVotes} from "../../mock/MockDAO.sol";
import {MockERC20} from "../../mock/MockERC20.sol";

contract UnitTestVoltV2GovCompatibility is DSTest {
    using SafeCast for *;

    VoltV2 private voltV2;
    ICore private core;
    MockDAO private mockDAO;
    MockERC20 private mockToken;
    TimelockController private timelock;

    VoltTestAddresses public addresses = getAddresses();

    address proposerCancellerExecutor = address(0x123);
    address userWithVolt = address(0xFFF);

    Vm private vm = Vm(HEVM_ADDRESS);

    uint256 public quorum = 1_000_000e18;

    function setUp() public {
        core = getCore();

        address[] memory proposerCancellerAddresses = new address[](1);
        proposerCancellerAddresses[0] = proposerCancellerExecutor;

        address[] memory executorAddresses = new address[](1);
        executorAddresses[0] = proposerCancellerExecutor;

        timelock = new TimelockController(
            600,
            proposerCancellerAddresses,
            executorAddresses
        );

        voltV2 = new VoltV2(address(core));
        mockDAO = new MockDAO(IVotes(address(voltV2)), timelock);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(mockDAO));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(mockDAO));

        mockToken = new MockERC20();
        mockToken.mint(address(timelock), 1_000_000e18);
    }

    function testUserWithNoVoltCanPropose() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description,

        ) = _createDummyProposal();

        uint256 noVoltProposalId = mockDAO.propose(
            targets,
            values,
            calldatas,
            description
        );

        assertEq(uint8(mockDAO.state(noVoltProposalId)), 0); // Pending
        vm.roll(block.number + 1);

        assertEq(uint8(mockDAO.state(noVoltProposalId)), 1); // Active
    }

    function testProposalExecutes() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description,
            bytes32 descriptionHash
        ) = _createDummyProposal();

        vm.prank(addresses.minterAddress);
        voltV2.mint(userWithVolt, quorum);

        vm.prank(userWithVolt);
        voltV2.delegate(userWithVolt);

        uint256 proposalId = mockDAO.propose(
            targets,
            values,
            calldatas,
            description
        );

        // Advance past the 1 voting block
        vm.roll(block.number + 1);

        // Cast a vote for the proposal, in excess of quorum
        vm.prank(userWithVolt);
        mockDAO.castVote(proposalId, 1);

        (, , , , , uint256 forVotes, , , , ) = mockDAO.proposals(proposalId);

        assertEq(
            mockDAO.getReceipt(proposalId, userWithVolt).votes,
            voltV2.getVotes(userWithVolt)
        );

        assertEq(forVotes, quorum);
        assertEq(forVotes, voltV2.getVotes(userWithVolt));

        vm.roll(block.number + 2);

        vm.startPrank(proposerCancellerExecutor);
        mockDAO.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.number + timelock.getMinDelay());

        mockDAO.execute(targets, values, calldatas, descriptionHash);
        vm.stopPrank();

        assertEq(mockToken.balanceOf(userWithVolt), 1_000_000e18);
    }

    function testProposalRejectsIfNotQuorum() public {
        address userWithInsufficientVolt = address(0xFFF);
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description,
            bytes32 descriptionHash
        ) = _createDummyProposal();

        vm.prank(userWithInsufficientVolt);
        uint256 proposalId = mockDAO.propose(
            targets,
            values,
            calldatas,
            description
        );

        vm.prank(addresses.minterAddress);
        voltV2.mint(userWithInsufficientVolt, quorum - 1);

        vm.prank(userWithInsufficientVolt);
        voltV2.delegate(userWithInsufficientVolt);

        // Advance past the 1 voting block
        vm.roll(block.number + 1);

        vm.prank(userWithInsufficientVolt);
        mockDAO.castVote(proposalId, 1);

        (, , , , , uint256 forVotes, , , , ) = mockDAO.proposals(proposalId);

        assertEq(
            mockDAO.getReceipt(proposalId, userWithInsufficientVolt).votes,
            voltV2.getVotes(userWithInsufficientVolt)
        );

        assertEq(forVotes, quorum - 1);
        assertEq(forVotes, voltV2.getVotes(userWithInsufficientVolt));

        vm.roll(block.number + 2);

        vm.startPrank(proposerCancellerExecutor);
        vm.expectRevert(bytes("Governor: proposal not successful"));
        mockDAO.queue(targets, values, calldatas, descriptionHash);
        vm.stopPrank();
    }

    function testMultiUserVotesNotReachQuorum(uint16[8] memory amounts) public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description,
            bytes32 descriptionHash
        ) = _createDummyProposal();

        uint256 proposalId = mockDAO.propose(
            targets,
            values,
            calldatas,
            description
        );

        address[] memory voters = new address[](8);
        uint256 totalVotes;
        for (uint256 i = 0; i < 8; i++) {
            voters[i] = vm.addr(i + 1); // populate voters array, make sure no addresses are the same
            vm.prank(addresses.minterAddress);
            voltV2.mint(voters[i], amounts[i]);
            totalVotes += amounts[i];

            vm.prank(voters[i]);
            voltV2.delegate(voters[i]);

            vm.roll(block.number + 1); // roll to to start voting period

            vm.prank(voters[i]);
            mockDAO.castVote(proposalId, 1);

            assertEq(
                mockDAO.getReceipt(proposalId, voters[i]).votes,
                voltV2.getVotes(voters[i])
            );
            vm.roll(block.number - 1); // roll back the block number for the next voter
        }

        vm.roll(block.number + 2); // reach end of voting period

        (, , , , , uint256 forVotes, , , , ) = mockDAO.proposals(proposalId);
        assertEq(forVotes, totalVotes);

        vm.startPrank(proposerCancellerExecutor);
        vm.expectRevert(bytes("Governor: proposal not successful"));
        mockDAO.queue(targets, values, calldatas, descriptionHash);
        vm.stopPrank();
    }

    function _createDummyProposal()
        internal
        view
        returns (
            address[] memory,
            uint256[] memory,
            bytes[] memory,
            string memory,
            bytes32
        )
    {
        address[] memory targets = new address[](1);
        targets[0] = address(mockToken);

        uint256[] memory values = new uint256[](1);
        values[0] = uint256(0);

        bytes[] memory calldatas = new bytes[](1);
        bytes memory data = abi.encodeWithSignature(
            "transfer(address,uint256)",
            userWithVolt,
            1_000_000e18
        );
        calldatas[0] = data;

        string memory description = "Dummy proposal";
        bytes32 descriptionHash = keccak256(bytes(description));
        return (targets, values, calldatas, description, descriptionHash);
    }
}
