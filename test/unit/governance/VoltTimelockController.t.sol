// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Test} from "@forge-std/Test.sol";
import {CoreV2} from "@voltprotocol/core/CoreV2.sol";
import {MockERC20} from "@test/mock/MockERC20.sol";
import {getCoreV2} from "@test/unit/utils/Fixtures.sol";
import {VoltRoles} from "@voltprotocol/core/VoltRoles.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {VoltTimelockController} from "@voltprotocol/governance/VoltTimelockController.sol";
import {TestAddresses as addresses} from "@test/unit/utils/TestAddresses.sol";

contract VoltTimelockControllerUnitTest is Test {
    CoreV2 private core;
    MockERC20 private token;
    VoltTimelockController private timelock;

    uint256 private constant _TIMELOCK_MIN_DELAY = 12345;

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

        // create timelock roles
        vm.startPrank(addresses.governorAddress);
        core.createRole(VoltRoles.TIMELOCK_EXECUTOR, VoltRoles.GOVERNOR);
        core.createRole(VoltRoles.TIMELOCK_CANCELLER, VoltRoles.GOVERNOR);
        core.createRole(VoltRoles.TIMELOCK_PROPOSER, VoltRoles.GOVERNOR);
        vm.stopPrank();
    }

    function testPublicGetters() public {
        assertEq(address(timelock.core()), address(core));
        assertEq(timelock.getMinDelay(), _TIMELOCK_MIN_DELAY);
    }

    function testHasRole() public {
        assertEq(
            timelock.hasRole(VoltRoles.TIMELOCK_PROPOSER, address(this)),
            false
        );
        assertEq(
            timelock.hasRole(VoltRoles.TIMELOCK_EXECUTOR, address(this)),
            false
        );
        assertEq(
            timelock.hasRole(VoltRoles.TIMELOCK_CANCELLER, address(this)),
            false
        );

        vm.prank(addresses.governorAddress);
        core.grantRole(VoltRoles.TIMELOCK_PROPOSER, address(this));
        assertEq(
            timelock.hasRole(VoltRoles.TIMELOCK_PROPOSER, address(this)),
            true
        );
        assertEq(
            timelock.hasRole(VoltRoles.TIMELOCK_EXECUTOR, address(this)),
            false
        );
        assertEq(
            timelock.hasRole(VoltRoles.TIMELOCK_CANCELLER, address(this)),
            false
        );

        vm.prank(addresses.governorAddress);
        core.grantRole(VoltRoles.TIMELOCK_EXECUTOR, address(this));
        assertEq(
            timelock.hasRole(VoltRoles.TIMELOCK_PROPOSER, address(this)),
            true
        );
        assertEq(
            timelock.hasRole(VoltRoles.TIMELOCK_EXECUTOR, address(this)),
            true
        );
        assertEq(
            timelock.hasRole(VoltRoles.TIMELOCK_CANCELLER, address(this)),
            false
        );

        vm.prank(addresses.governorAddress);
        core.grantRole(VoltRoles.TIMELOCK_CANCELLER, address(this));
        assertEq(
            timelock.hasRole(VoltRoles.TIMELOCK_PROPOSER, address(this)),
            true
        );
        assertEq(
            timelock.hasRole(VoltRoles.TIMELOCK_EXECUTOR, address(this)),
            true
        );
        assertEq(
            timelock.hasRole(VoltRoles.TIMELOCK_CANCELLER, address(this)),
            true
        );
    }

    function testScheduleBatchExecuteBatch() public {
        // function parameters
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSelector(
            VoltTimelockControllerUnitTest.__dummyCall.selector,
            12345
        );
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256(bytes("dummy call"));

        // get batch id
        bytes32 id = timelock.hashOperationBatch(
            targets,
            values,
            payloads,
            0,
            salt
        );

        // grant proposer and executor role to self
        vm.startPrank(addresses.governorAddress);
        core.grantRole(VoltRoles.TIMELOCK_PROPOSER, address(this));
        core.grantRole(VoltRoles.TIMELOCK_EXECUTOR, address(this));
        vm.stopPrank();

        assertEq(timelock.getTimestamp(id), 0);
        assertEq(timelock.isOperation(id), false);
        assertEq(timelock.isOperationPending(id), false);
        assertEq(timelock.isOperationReady(id), false);
        assertEq(timelock.isOperationDone(id), false);

        // schedule batch
        timelock.scheduleBatch(
            targets,
            values,
            payloads,
            predecessor,
            salt,
            _TIMELOCK_MIN_DELAY
        );

        assertEq(
            timelock.getTimestamp(id),
            block.timestamp + _TIMELOCK_MIN_DELAY
        );
        assertEq(timelock.isOperation(id), true);
        assertEq(timelock.isOperationPending(id), true);
        assertEq(timelock.isOperationReady(id), false);
        assertEq(timelock.isOperationDone(id), false);

        // fast forward time
        vm.warp(block.timestamp + _TIMELOCK_MIN_DELAY);

        assertEq(timelock.isOperation(id), true);
        assertEq(timelock.isOperationPending(id), true);
        assertEq(timelock.isOperationReady(id), true);
        assertEq(timelock.isOperationDone(id), false);

        // execute
        timelock.executeBatch(targets, values, payloads, predecessor, salt);

        assertEq(timelock.getTimestamp(id), 1); // _DONE_TIMESTAMP = 1
        assertEq(timelock.isOperation(id), true);
        assertEq(timelock.isOperationPending(id), false);
        assertEq(timelock.isOperationReady(id), false);
        assertEq(timelock.isOperationDone(id), true);
    }

    function testScheduleBatchCancel() public {
        // function parameters
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSelector(
            VoltTimelockControllerUnitTest.__dummyCall.selector,
            12345
        );
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256(bytes("dummy call"));

        // get batch id
        bytes32 id = timelock.hashOperationBatch(
            targets,
            values,
            payloads,
            0,
            salt
        );

        // grant proposer and canceller role to self
        vm.startPrank(addresses.governorAddress);
        core.grantRole(VoltRoles.TIMELOCK_PROPOSER, address(this));
        core.grantRole(VoltRoles.TIMELOCK_CANCELLER, address(this));
        vm.stopPrank();

        assertEq(timelock.getTimestamp(id), 0);
        assertEq(timelock.isOperation(id), false);
        assertEq(timelock.isOperationPending(id), false);
        assertEq(timelock.isOperationReady(id), false);
        assertEq(timelock.isOperationDone(id), false);

        // schedule batch
        timelock.scheduleBatch(
            targets,
            values,
            payloads,
            predecessor,
            salt,
            _TIMELOCK_MIN_DELAY
        );

        assertEq(
            timelock.getTimestamp(id),
            block.timestamp + _TIMELOCK_MIN_DELAY
        );
        assertEq(timelock.isOperation(id), true);
        assertEq(timelock.isOperationPending(id), true);
        assertEq(timelock.isOperationReady(id), false);
        assertEq(timelock.isOperationDone(id), false);

        // cancel
        timelock.cancel(id);

        assertEq(timelock.getTimestamp(id), 0);
        assertEq(timelock.isOperation(id), false);
        assertEq(timelock.isOperationPending(id), false);
        assertEq(timelock.isOperationReady(id), false);
        assertEq(timelock.isOperationDone(id), false);
    }

    function testUpdateDelay() public {
        // only the timelock can update its own delay
        vm.expectRevert("TimelockController: caller must be timelock");
        timelock.updateDelay(_TIMELOCK_MIN_DELAY / 2);

        // grant proposer and executor role to self
        vm.startPrank(addresses.governorAddress);
        core.grantRole(VoltRoles.TIMELOCK_PROPOSER, address(this));
        core.grantRole(VoltRoles.TIMELOCK_EXECUTOR, address(this));
        vm.stopPrank();

        // schedule an action to update delay
        bytes memory data = abi.encodeWithSelector(
            TimelockController.updateDelay.selector,
            _TIMELOCK_MIN_DELAY / 2
        );
        bytes32 id = timelock.hashOperation(
            address(timelock),
            0,
            data,
            bytes32(0),
            keccak256(bytes("dummy call"))
        );
        assertEq(timelock.isOperation(id), false);
        timelock.schedule(
            address(timelock), // address target
            0, // uint256 value
            data, // bytes data
            bytes32(0), // bytes32 predecessor
            keccak256(bytes("dummy call")), // bytes32 salt
            _TIMELOCK_MIN_DELAY // uint256 delay
        );
        assertEq(timelock.isOperation(id), true);

        // fast forward in time & execute
        vm.warp(block.timestamp + _TIMELOCK_MIN_DELAY);
        timelock.execute(
            address(timelock), // address target
            0, // uint256 value
            data, // bytes data
            bytes32(0), // bytes32 predecessor
            keccak256(bytes("dummy call")) // bytes32 salt
        );
        assertEq(timelock.isOperationDone(id), true);
        assertEq(timelock.getMinDelay(), _TIMELOCK_MIN_DELAY / 2);
    }
}
