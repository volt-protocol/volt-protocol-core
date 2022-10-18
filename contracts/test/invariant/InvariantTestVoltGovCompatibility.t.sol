// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {DSTest} from "../unit/utils/DSTest.sol";
import {DSInvariantTest} from "../unit/utils/DSInvariantTest.sol";
import {Vm} from "../unit/utils/Vm.sol";
import {ICore} from "../../core/ICore.sol";
import {getCore, getAddresses, VoltTestAddresses} from "../unit/utils/Fixtures.sol";
import {VoltV2} from "../../volt/VoltV2.sol";
import {MockDAO, IVotes} from "../../mock/MockDAO.sol";
import {MockERC20} from "../../mock/MockERC20.sol";

contract InvariantTestVoltGovCompatibility is DSTest, DSInvariantTest {
    VoltTester public voltTester;
    VoltV2 public volt;
    ICore public core;

    MockDAO public mockDAO;
    MockERC20 public mockToken;
    TimelockController public timelock;

    uint256 proposalId;
    address proposerCancellerExecutor = address(this);

    Vm private vm = Vm(HEVM_ADDRESS);

    function setUp() public {
        core = getCore();
        volt = new VoltV2(address(core));

        address[] memory proposerCancellerAddresses = new address[](1);
        proposerCancellerAddresses[0] = proposerCancellerExecutor;

        address[] memory executorAddresses = new address[](1);
        executorAddresses[0] = proposerCancellerExecutor;

        timelock = new TimelockController(
            600,
            proposerCancellerAddresses,
            executorAddresses
        );

        volt = new VoltV2(address(core));
        mockDAO = new MockDAO(IVotes(address(volt)), timelock);

        mockToken = new MockERC20();
        mockToken.mint(address(timelock), 1_000_000e18);

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description,

        ) = _createDummyProposal();

        proposalId = mockDAO.propose(targets, values, calldatas, description);
        vm.roll(block.timestamp + 1);

        voltTester = new VoltTester(volt, mockDAO, proposalId);
        addTargetContract(address(voltTester));
    }

    function invariantUserVoting() public {
        address[] memory allUsers = new address[](voltTester.allUserLength());
        uint256 totalVotes;

        for (uint256 i = 0; i < voltTester.allUserLength(); i++) {
            allUsers[i] = voltTester.allUsers(i);
            totalVotes += volt.balanceOf(allUsers[i]);

            assertEq(
                volt.getVotes(allUsers[i]),
                voltTester.votingPower(allUsers[i])
            );
            assertEq(
                mockDAO.getReceipt(proposalId, allUsers[i]).votes,
                volt.getVotes(allUsers[i])
            );
            assertTrue(mockDAO.hasVoted(proposalId, allUsers[i]));
        }
        assertEq(totalVotes, volt.totalSupply());

        (, , , , , uint256 forVotes, , , , ) = mockDAO.proposals(proposalId);
        assertEq(forVotes, totalVotes);
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
            address(0xFFF),
            1_000_000e18
        );
        calldatas[0] = data;

        string memory description = "Dummy proposal";
        bytes32 descriptionHash = keccak256(bytes(description));
        return (targets, values, calldatas, description, descriptionHash);
    }
}

contract VoltTester is DSTest {
    VoltV2 public volt;
    MockDAO public mockDAO;
    uint256 public proposalId;

    VoltTestAddresses public addresses = getAddresses();
    Vm private vm = Vm(HEVM_ADDRESS);
    mapping(address => uint256) public balances;
    mapping(address => bool) public isUser;
    mapping(address => uint256) public votingPower;
    mapping(address => bool) public hasVoted;

    address[] public allUsers;
    uint256 public sum;

    constructor(
        VoltV2 _volt,
        MockDAO _mockDAO,
        uint256 _proposalId
    ) {
        volt = _volt;
        mockDAO = _mockDAO;
        proposalId = _proposalId;
    }

    function mint(address to, uint256 amount) public {
        vm.prank(addresses.governorAddress);
        volt.mint(to, amount);
        unchecked {
            sum += amount;
            checkpointUser(to);
            balances[to] += amount;
        }
    }

    function allUserLength() public returns (uint256) {
        return allUsers.length;
    }

    function checkpointUser(address user) internal {
        if (isUser[user] == false) {
            allUsers.push(user);
            isUser[user] = true;
        }
        vm.prank(user);
        volt.delegate(user);
        votingPower[user] = volt.getVotes(user);
        vote(user);
    }

    function vote(address user) internal {
        if (!hasVoted[user]) {
            mockDAO.castVote(proposalId, 1);
            hasVoted[user] = true;
        }
    }
}
