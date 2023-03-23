// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Test} from "@forge-std/Test.sol";
import {CoreV2} from "@voltprotocol/core/CoreV2.sol";
import {MockERC20} from "@test/mock/MockERC20.sol";
import {getCoreV2} from "@test/unit/utils/Fixtures.sol";
import {VoltRoles} from "@voltprotocol/core/VoltRoles.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {VoltVetoGovernor} from "@voltprotocol/governance/VoltVetoGovernor.sol";
import {VoltTimelockController} from "@voltprotocol/governance/VoltTimelockController.sol";
import {TestAddresses as addresses} from "@test/unit/utils/TestAddresses.sol";

contract VoltVetoGovernorUnitTest is Test {
    CoreV2 private core;
    MockERC20 private token;
    VoltTimelockController private timelock;
    VoltVetoGovernor private governor;

    uint256 private constant _TIMELOCK_MIN_DELAY = 12345;
    uint256 private constant _VETO_QUORUM = 100e18;

    uint256 __lastCallValue = 0;

    function __dummyCall(uint256 val) external {
        __lastCallValue = val;
    }

    function setUp() public {
        // vm state needs a coherent timestamp & block for timelock logic
        vm.warp(1677869014);
        vm.roll(16749838);

        // create contracts
        core = CoreV2(address(getCoreV2()));
        token = new MockERC20();
        timelock = new VoltTimelockController(
            address(core),
            _TIMELOCK_MIN_DELAY
        );
        governor = new VoltVetoGovernor(
            address(core),
            address(timelock),
            address(token),
            _VETO_QUORUM
        );

        // grant role
        vm.startPrank(addresses.governorAddress);
        core.createRole(VoltRoles.TIMELOCK_EXECUTOR, VoltRoles.GOVERNOR);
        core.grantRole(VoltRoles.TIMELOCK_EXECUTOR, address(0));
        core.createRole(VoltRoles.TIMELOCK_CANCELLER, VoltRoles.GOVERNOR);
        core.grantRole(VoltRoles.TIMELOCK_CANCELLER, address(governor));
        core.createRole(VoltRoles.TIMELOCK_PROPOSER, VoltRoles.GOVERNOR);
        core.grantRole(VoltRoles.TIMELOCK_PROPOSER, address(this));
        vm.stopPrank();
    }

    function testPublicGetters() public {
        assertEq(governor.quorum(0), _VETO_QUORUM);
        assertEq(governor.timelock(), address(timelock));
        assertEq(governor.COUNTING_MODE(), "support=bravo&quorum=against");
        assertEq(governor.proposalThreshold(), 0);
        assertEq(governor.votingDelay(), 0);
        assertEq(governor.votingPeriod(), 2425847);
        assertEq(address(governor.token()), address(token));
        assertEq(governor.name(), "Volt Protocol Veto Governor");
        assertEq(governor.version(), "1");
    }

    function testSuccessfulVeto() public {
        // schedule an action in the timelock
        bytes32 timelockId = _queueDummyTimelockAction(12345);

        // check status in the timelock
        assertEq(timelock.isOperationPending(timelockId), true);
        assertEq(timelock.isOperationReady(timelockId), false);
        assertEq(timelock.isOperationDone(timelockId), false);

        // create a veto proposal
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 10);
        token.mockSetVotes(address(this), _VETO_QUORUM);

        uint256 proposalId = governor.createVeto(timelockId);
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Pending)
        );
        assertEq(uint256(governor.proposalSnapshot(proposalId)), block.number);
        assertEq(
            uint256(governor.proposalDeadline(proposalId)),
            block.number + 2425847
        );

        // cannot vote in the same block as the propose()
        assertEq(governor.getVotes(address(this), block.number), _VETO_QUORUM); // we have the votes
        assertEq(governor.hasVoted(proposalId, address(this)), false); // we have not voted
        (
            uint256 againstVotes,
            uint256 forVotes,
            uint256 abstainVotes
        ) = governor.proposalVotes(proposalId);
        assertEq(againstVotes, 0); // nobody voted
        assertEq(forVotes, 0); // nobody voted
        assertEq(abstainVotes, 0); // nobody voted
        vm.expectRevert("Governor: vote not currently active");
        governor.castVote(proposalId, uint8(VoltVetoGovernor.VoteType.Against));

        // on next block, the vote is active
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 10);
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Active)
        );

        // we vote and reach quorum
        governor.castVote(proposalId, uint8(VoltVetoGovernor.VoteType.Against));
        assertEq(governor.hasVoted(proposalId, address(this)), true); // we have voted
        (againstVotes, forVotes, abstainVotes) = governor.proposalVotes(
            proposalId
        );
        assertEq(againstVotes, _VETO_QUORUM); // we voted and reached quorum
        assertEq(forVotes, 0);
        assertEq(abstainVotes, 0);

        // execute
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Succeeded)
        );
        governor.executeVeto(timelockId);
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Executed)
        );

        // check the proposal has been cleared out of the timelock
        assertEq(timelock.isOperation(timelockId), false);
    }

    function testVetoQuorumNotReached() public {
        // schedule an action in the timelock
        bytes32 timelockId = _queueDummyTimelockAction(12345);

        // create a veto proposal
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 10);
        token.mockSetVotes(address(this), _VETO_QUORUM / 2);
        uint256 proposalId = governor.createVeto(timelockId);
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Pending)
        );

        // cannot vote in the same block as the propose()
        // on next block, the vote is active
        // we vote and do not reach quorum
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 10);
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Active)
        );
        governor.castVote(proposalId, uint8(VoltVetoGovernor.VoteType.Against));
        // cannot vote twice
        vm.expectRevert("VoltVetoGovernor: vote already cast");
        governor.castVote(proposalId, uint8(VoltVetoGovernor.VoteType.Against));
        // still Active after voting because quorum is not reached
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Active)
        );

        // fast forward time, the action is ready in the timelock and veto vote expired
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + _TIMELOCK_MIN_DELAY);
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Defeated)
        );

        // cannot execute veto, it is too late
        vm.expectRevert("Governor: proposal not successful");
        governor.executeVeto(timelockId);

        // the timelock action can be executed
        assertEq(timelock.isOperation(timelockId), true);
        assertEq(timelock.isOperationPending(timelockId), true);
        assertEq(timelock.isOperationReady(timelockId), true);
        assertEq(timelock.isOperationDone(timelockId), false);

        // execute
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSelector(
            VoltVetoGovernorUnitTest.__dummyCall.selector,
            12345
        );
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256(bytes("dummy call"));
        timelock.executeBatch(targets, values, payloads, predecessor, salt);

        // if timelock action is executed, status id Defeated
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Defeated)
        );
    }

    function testVetoAlreadyCancelledInTimelock() public {
        // schedule an action in the timelock
        bytes32 timelockId = _queueDummyTimelockAction(12345);

        // create a veto proposal
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 10);
        token.mockSetVotes(address(this), _VETO_QUORUM);
        uint256 proposalId = governor.createVeto(timelockId);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 10);
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Active)
        );

        // vote for the proposal
        governor.castVote(proposalId, uint8(VoltVetoGovernor.VoteType.Against));
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Succeeded)
        );

        // cancel in the timelock
        vm.prank(addresses.governorAddress);
        core.grantRole(VoltRoles.TIMELOCK_CANCELLER, address(this));
        timelock.cancel(timelockId);

        // check proposal state
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Canceled)
        );

        // cannot vote for veto anymore
        vm.expectRevert("Governor: vote not currently active");
        governor.castVote(proposalId, uint8(VoltVetoGovernor.VoteType.Against));
    }

    function testCanOnlyVoteAgainst() public {
        // schedule an action in the timelock
        bytes32 timelockId = _queueDummyTimelockAction(12345);

        // create a veto proposal
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 10);
        token.mockSetVotes(address(this), _VETO_QUORUM);
        uint256 proposalId = governor.createVeto(timelockId);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 10);

        // cannot vote For
        vm.expectRevert(
            "VoltVetoGovernor: can only vote against in veto proposals"
        );
        governor.castVote(proposalId, uint8(VoltVetoGovernor.VoteType.For));

        // cannot vote Abstain
        vm.expectRevert(
            "VoltVetoGovernor: can only vote against in veto proposals"
        );
        governor.castVote(proposalId, uint8(VoltVetoGovernor.VoteType.Abstain));
    }

    function testSetQuorum() public {
        // non-governor cannot set quorum
        vm.expectRevert("UNAUTHORIZED");
        governor.setQuorum(_VETO_QUORUM * 2);
        assertEq(governor.quorum(block.number), _VETO_QUORUM);

        // governor can set quorum
        vm.prank(addresses.governorAddress);
        governor.setQuorum(_VETO_QUORUM * 2);
        assertEq(governor.quorum(block.number), _VETO_QUORUM * 2);
    }

    function testProposeArbitraryCallsReverts() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory payloads = new bytes[](1);
        vm.expectRevert("VoltVetoGovernor: cannot propose arbitrary actions");
        governor.propose(targets, values, payloads, "test");
    }

    function testUpdateTimelock() public {
        // non-governor cannot set timelock
        vm.expectRevert("UNAUTHORIZED");
        governor.updateTimelock(address(this));
        assertEq(governor.timelock(), address(timelock));

        // governor can set timelock
        vm.prank(addresses.governorAddress);
        governor.updateTimelock(address(this));
        assertEq(governor.timelock(), address(this));
    }

    function testStateUnknownProposal() public {
        vm.expectRevert("Governor: unknown proposal id");
        governor.state(575445);
    }

    function _queueDummyTimelockAction(
        uint256 number
    ) internal returns (bytes32) {
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSelector(
            VoltVetoGovernorUnitTest.__dummyCall.selector,
            number
        );
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256(bytes("dummy call"));
        timelock.scheduleBatch(
            targets,
            values,
            payloads,
            predecessor,
            salt,
            _TIMELOCK_MIN_DELAY
        );
        bytes32 timelockId = timelock.hashOperationBatch(
            targets,
            values,
            payloads,
            0,
            salt
        );

        return timelockId;
    }
}