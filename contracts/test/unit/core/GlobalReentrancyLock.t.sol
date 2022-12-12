// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Vm} from "./../utils/Vm.sol";
import {Volt} from "../../../volt/Volt.sol";
import {Vcon} from "../../../vcon/Vcon.sol";
import {IVolt} from "../../../volt/Volt.sol";
import {ICore} from "../../../core/ICore.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {CoreV2} from "../../../core/CoreV2.sol";
import {VoltRoles} from "../../../core/VoltRoles.sol";
import {MockERC20} from "./../../../mock/MockERC20.sol";
import {MockReentrancyLock} from "./../../../mock/MockReentrancyLock.sol";
import {MockReentrancyLockFailure} from "./../../../mock/MockReentrancyLockFailure.sol";
import {TestAddresses as addresses} from "../utils/TestAddresses.sol";
import {getCoreV2} from "./../utils/Fixtures.sol";

contract UnitTestGlobalReentrancyLock is DSTest {
    /// @notice emitted when governor does an emergency lock
    event EmergencyLock(address indexed sender, uint256 timestamp);

    CoreV2 private core;

    Vm public constant vm = Vm(HEVM_ADDRESS);
    MockERC20 volt;
    MockReentrancyLock private lock;
    Vcon vcon;

    function setUp() public {
        volt = new MockERC20();

        // Deploy Core from Governor address
        vm.startPrank(addresses.governorAddress);
        core = new CoreV2(address(volt));
        vcon = new Vcon(addresses.governorAddress, addresses.governorAddress);
        lock = new MockReentrancyLock(address(core));
        core.grantLocker(address(lock));

        vm.stopPrank();
    }

    function testSetup() public {
        assertEq(address(core.volt()), address(volt));
        assertEq(address(core.vcon()), address(0)); /// vcon starts set to address 0

        assertTrue(core.isGovernor(address(core))); /// core contract is governor
        assertTrue(core.isGovernor(addresses.governorAddress)); /// msg.sender of contract is governor

        assertTrue(core.isUnlocked()); /// core starts out unlocked
        assertTrue(!core.isLocked()); /// core starts out not locked
        assertEq(core.lastSender(), address(0));
        assertEq(core.lastBlockEntered(), 0);

        assertTrue(core.isLocker(address(lock)));
    }

    function testLockFailsWithoutRole() public {
        vm.prank(addresses.governorAddress);
        core.revokeRole(VoltRoles.LOCKER, address(lock));
        assertTrue(!core.isLocker(address(lock)));

        vm.expectRevert("GlobalReentrancyLock: missing locker role");
        lock.testGlobalLock();

        assertTrue(core.isUnlocked());
        assertTrue(!core.isLocked());
    }

    function testLockFailsWithoutRoleRevokeGlobalLocker() public {
        vm.prank(addresses.governorAddress);
        core.revokeLocker(address(lock));
        assertTrue(!core.isLocker(address(lock)));

        vm.expectRevert("GlobalReentrancyLock: missing locker role");
        lock.testGlobalLock();

        assertTrue(core.isUnlocked());
        assertTrue(!core.isLocked());
    }

    function testLockSucceedsWithRole(uint8 numRuns) public {
        for (uint256 i = 0; i < numRuns; i++) {
            assertTrue(core.isUnlocked());
            assertTrue(!core.isLocked());
            assertEq(lock.lastBlockNumber(), core.lastBlockEntered());

            lock.testGlobalLock();

            assertTrue(core.isUnlocked());
            assertTrue(!core.isLocked());
            assertEq(core.lockLevel(), 0);
            assertEq(lock.lastBlockNumber(), core.lastBlockEntered());
            assertEq(core.lastSender(), address(lock));
        }
    }

    function testLockSucceedsWithRole(
        uint8 numRuns,
        address[8] memory lockers
    ) public {
        for (uint256 i = 0; i < numRuns; i++) {
            assertTrue(core.isUnlocked());
            assertTrue(!core.isLocked());

            address toPrank = lockers[i > 7 ? 7 : i];
            if (!core.isLocker(toPrank)) {
                vm.prank(addresses.governorAddress);
                core.grantLocker(toPrank);
            }

            vm.prank(toPrank);
            core.lock(1);

            assertTrue(core.isLocked());
            assertTrue(!core.isUnlocked());
            assertEq(core.lockLevel(), 1);
            assertEq(core.lastBlockEntered(), block.number);
            assertEq(toPrank, core.lastSender());

            vm.prank(toPrank);
            core.unlock(0);

            assertEq(core.lockLevel(), 0);
            assertTrue(core.isUnlocked());
            assertTrue(!core.isLocked());
            assertEq(toPrank, core.lastSender());

            vm.roll(block.number + 1);
        }
    }

    function testLockLevel2SucceedsWithRole(
        uint8 numRuns,
        address[8] memory lockers
    ) public {
        for (uint256 i = 0; i < numRuns; i++) {
            assertTrue(core.isUnlocked());
            assertTrue(!core.isLocked());

            address toPrank = lockers[i > 7 ? 7 : i];
            if (!core.isLocker(toPrank)) {
                vm.prank(addresses.governorAddress);
                core.grantLocker(toPrank);
            }

            vm.startPrank(toPrank);

            core.lock(1);
            core.lock(2);

            assertEq(core.lockLevel(), 2);
            assertEq(core.lastBlockEntered(), block.number);
            assertEq(toPrank, core.lastSender());

            core.unlock(1);
            core.unlock(0);

            vm.stopPrank();

            assertEq(core.lockLevel(), 0);
            assertTrue(core.isUnlocked());
            assertTrue(!core.isLocked());
            assertEq(toPrank, core.lastSender());
            vm.roll(block.number + 1);
        }
    }

    function testLockLevel1And2SucceedsWithRole(
        uint8 numRuns,
        address[8] memory lockers
    ) public {
        /// level
        for (uint256 i = 0; i < numRuns; i++) {
            assertTrue(core.isUnlocked());
            assertTrue(!core.isLocked());
            assertEq(core.lockLevel(), 0);

            address toPrank = lockers[i > 7 ? 7 : i];
            if (!core.isLocker(toPrank)) {
                vm.prank(addresses.governorAddress);
                core.grantLocker(toPrank);
            }

            vm.prank(toPrank);
            core.lock(1);

            assertEq(core.lockLevel(), 1);
            assertEq(core.lastBlockEntered(), block.number);
            assertEq(toPrank, core.lastSender());

            if (!core.isLocker(toPrank)) {
                vm.prank(addresses.governorAddress);
                core.grantLocker(toPrank);
            }

            vm.prank(toPrank);
            core.lock(2);

            assertTrue(core.isLocked());
            assertEq(core.lockLevel(), 2);

            assertEq(core.lastBlockEntered(), block.number);
            assertEq(toPrank, core.lastSender());

            vm.prank(toPrank);
            core.unlock(1);

            assertEq(core.lockLevel(), 1);
            assertTrue(!core.isUnlocked());
            assertTrue(core.isLocked());
            assertEq(toPrank, core.lastSender());

            assertEq(toPrank, core.lastSender());
            vm.prank(toPrank);
            core.unlock(0);

            assertTrue(!core.isLocked());
            assertEq(core.lockLevel(), 0);
            assertTrue(core.isUnlocked()); /// core is fully unlocked
            assertEq(toPrank, core.lastSender());

            vm.roll(block.number + 1);
        }
    }

    /// create a separate contract,
    /// call globalReentrancyFails on that contract,
    /// which calls globalLock on the MockReentrancyLock contract,
    /// MockReentrancyLock fails because the system has already been entered globally
    function testLockStopsReentrancy() public {
        MockReentrancyLockFailure lock2 = new MockReentrancyLockFailure(
            address(core),
            address(lock)
        );
        vm.prank(addresses.governorAddress);
        core.grantLocker(address(lock2));

        /// CoreRef modifier globalLock enforces level
        vm.expectRevert("CoreRef: cannot lock less than current level");
        lock2.globalReentrancyFails();

        assertTrue(core.isUnlocked());
        assertTrue(!core.isLocked());
        assertEq(lock.lastBlockNumber(), core.lastBlockEntered());
    }

    function testGovernorSystemRecoveryFailsNotEntered() public {
        vm.prank(addresses.governorAddress);
        vm.expectRevert(
            "GlobalReentrancyLock: governor recovery, system not entered"
        );
        core.governanceEmergencyRecover();
    }

    function testGovernorEmergencyPauseSucceeds() public {
        vm.expectEmit(true, false, false, true, address(core));
        emit EmergencyLock(addresses.governorAddress, block.timestamp);

        vm.prank(addresses.governorAddress);
        core.governanceEmergencyPause();

        assertTrue(core.isLocked());
        assertEq(core.lockLevel(), 2);
    }

    function testGovernorEmergencyRecoversFromEmergencyPause() public {
        testGovernorEmergencyPauseSucceeds();

        vm.prank(addresses.governorAddress);
        core.governanceEmergencyRecover();

        assertTrue(!core.isLocked());
        assertEq(core.lockLevel(), 0);
    }

    function testGovernorSystemRecovery() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);

        core.lock(1);

        assertTrue(core.isLocked());
        assertTrue(!core.isUnlocked());
        assertEq(core.lockLevel(), 1);
        assertEq(core.lastBlockEntered(), block.number);

        vm.expectRevert(
            "GlobalReentrancyLock: cannot unlock in same block as lock"
        );
        core.governanceEmergencyRecover();

        vm.roll(block.number + 1);
        core.governanceEmergencyRecover();

        assertTrue(!core.isLocked());
        assertTrue(core.isUnlocked());
        assertTrue(core.lastBlockEntered() != block.number);
        assertEq(core.lockLevel(), 0);

        vm.stopPrank();
    }

    function testGovernorSystemRecoveryLevelTwoLocked() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);

        core.lock(1);
        core.lock(2);

        assertEq(core.lockLevel(), 2);
        assertTrue(core.isLocked());
        assertTrue(!core.isUnlocked());
        assertEq(core.lastBlockEntered(), block.number);

        vm.expectRevert(
            "GlobalReentrancyLock: cannot unlock in same block as lock"
        );
        core.governanceEmergencyRecover();

        vm.roll(block.number + 1);
        core.governanceEmergencyRecover();

        assertTrue(!core.isLocked());
        assertTrue(core.isUnlocked());
        assertEq(core.lockLevel(), 0);
        assertTrue(core.lastBlockEntered() != block.number);

        vm.stopPrank();
    }

    function testGovernorSystemRecoveryLevelTwoAndLevelOneLocked() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);

        core.lock(1);
        core.lock(2);

        assertTrue(core.isLocked());
        assertTrue(!core.isUnlocked());

        assertEq(core.lockLevel(), 2);
        assertEq(core.lastBlockEntered(), block.number);

        vm.expectRevert(
            "GlobalReentrancyLock: cannot unlock in same block as lock"
        );
        core.governanceEmergencyRecover();

        vm.roll(block.number + 1);
        core.governanceEmergencyRecover();

        assertTrue(!core.isLocked());
        assertTrue(core.isUnlocked());
        assertEq(core.lockLevel(), 0);
        assertTrue(core.lastBlockEntered() != block.number);
        vm.stopPrank();
    }

    function testOnlySameLockerCanUnlock() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);

        core.lock(1);
        core.grantLocker(address(this));

        vm.stopPrank();

        assertTrue(core.isLocker(address(this)));
        assertTrue(core.isLocked());
        assertTrue(!core.isUnlocked());
        assertEq(core.lastBlockEntered(), block.number);
        assertEq(core.lastSender(), addresses.governorAddress);

        vm.expectRevert("GlobalReentrancyLock: caller is not locker");
        core.unlock(0);

        vm.prank(addresses.governorAddress);
        core.unlock(0);

        assertTrue(!core.isLocked());
        assertTrue(core.isUnlocked());
        assertTrue(core.lastBlockEntered() == block.number);
        assertEq(core.lastSender(), addresses.governorAddress);
    }

    function testOnlySameLockerCanUnlockLevelTwo() public {
        vm.startPrank(addresses.governorAddress);

        core.grantLocker(addresses.governorAddress);

        core.lock(1);
        core.lock(2);

        vm.stopPrank();

        assertTrue(core.isLocker(addresses.governorAddress));

        assertEq(core.lockLevel(), 2);

        assertTrue(core.isLocked());
        assertTrue(!core.isUnlocked());

        assertEq(core.lastBlockEntered(), block.number);
        assertEq(core.lastSender(), addresses.governorAddress);

        vm.expectRevert("GlobalReentrancyLock: missing locker role");
        core.unlock(0);
    }

    function testInvalidStateReverts() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);
        core.grantLocker(address(this));

        core.lock(1);
        core.lock(2);
        vm.stopPrank();

        assertTrue(core.isLocker(addresses.governorAddress));
        assertTrue(core.isLocker(address(this)));

        assertEq(core.lockLevel(), 2);

        assertTrue(core.isLocked());
        assertTrue(!core.isUnlocked());

        assertEq(core.lastBlockEntered(), block.number);
        assertEq(core.lastSender(), addresses.governorAddress);

        vm.expectRevert("GlobalReentrancyLock: unlock level must be 1 lower");
        core.unlock(0);
    }

    function testLockingLevelTwoWhileLevelOneLockedDoesntSetSender() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);
        core.grantLocker(address(this));

        core.lock(1);
        assertEq(core.lockLevel(), 1);
        vm.stopPrank();

        core.lock(2);

        assertEq(core.lockLevel(), 2);

        assertTrue(core.isLocked());
        assertTrue(!core.isUnlocked());

        assertEq(core.lastBlockEntered(), block.number);
        assertEq(core.lastSender(), addresses.governorAddress);
    }

    function testUnlockingLevelOneWhileLevelTwoLockedFails() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(address(this));
        core.grantLocker(address(this));
        vm.stopPrank();

        core.lock(1);
        assertEq(core.lockLevel(), 1);
        core.lock(2);
        assertEq(core.lockLevel(), 2);

        vm.expectRevert("GlobalReentrancyLock: unlock level must be 1 lower");
        core.unlock(0);

        assertEq(core.lockLevel(), 2);
        assertTrue(core.isLocked());
        assertTrue(!core.isUnlocked());
        assertEq(core.lastBlockEntered(), block.number);
        assertEq(core.lastSender(), address(this));
    }

    function testCannotLockLevel2WhileLevelNotLocked() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);

        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        core.lock(2);

        vm.stopPrank();

        assertTrue(!core.isLocked());
        assertTrue(core.isUnlocked());
    }

    function testCannotLockLevel2WhileLevel1LockedPreviousBlock() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);

        core.lock(1);
        vm.roll(block.number + 1);
        vm.expectRevert("GlobalReentrancyLock: system not entered this block");
        core.lock(2);

        assertTrue(core.isLocked());
        assertTrue(!core.isUnlocked());
        assertTrue(core.lastBlockEntered() == block.number - 1);
        assertEq(core.lastSender(), addresses.governorAddress);

        vm.stopPrank();
    }

    function testCannotLockLevel2WhileLevel2Locked() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);

        core.lock(1);
        core.lock(2);
        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        core.lock(2);

        assertEq(core.lockLevel(), 2);
        assertTrue(core.isLocked());
        assertTrue(!core.isUnlocked());
        assertTrue(core.lastBlockEntered() == block.number);
        assertEq(core.lastSender(), addresses.governorAddress);

        vm.stopPrank();
    }

    function testCannotLockLevel3() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);

        core.lock(1);
        core.lock(2);
        vm.expectRevert("GlobalReentrancyLock: exceeds lock state");
        core.lock(3);

        assertEq(core.lockLevel(), 2);
        assertTrue(core.isLocked());
        assertTrue(!core.isUnlocked());
        assertEq(core.lastSender(), addresses.governorAddress);

        vm.stopPrank();
    }

    function testUnlockFailsSystemNotEntered() public {
        vm.startPrank(addresses.governorAddress);

        core.grantLocker(addresses.governorAddress);
        core.lock(1);
        core.unlock(0);
        vm.expectRevert("GlobalReentrancyLock: system not entered");
        core.unlock(1);
        vm.roll(block.number + 1);
        vm.expectRevert("GlobalReentrancyLock: not entered this block");
        core.unlock(0);

        vm.stopPrank();
    }

    function testUnlockFailsSystemNotEnteredBlockAdvanced() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);
        core.lock(1);
        core.unlock(0);
        vm.roll(block.number + 1);
        vm.expectRevert("GlobalReentrancyLock: not entered this block");
        core.unlock(0);
    }

    function testUnlockLevelTwoFailsSystemEnteredLevelOne() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);
        core.lock(1);
        vm.expectRevert("GlobalReentrancyLock: unlock level must be 1 lower");
        core.unlock(2);
        vm.expectRevert("GlobalReentrancyLock: unlock level must be 1 lower");
        core.unlock(1);
        vm.stopPrank();
    }

    function testUnlockLevel2FailsSystemNotEnteredBlockAdvanced() public {
        vm.startPrank(addresses.governorAddress);

        core.grantLocker(addresses.governorAddress);
        core.lock(1);
        core.lock(2);

        assertEq(core.lockLevel(), 2);
        assertTrue(core.isLocked());
        assertTrue(!core.isUnlocked());
        assertEq(core.lastSender(), addresses.governorAddress);

        core.unlock(1);
        core.unlock(0);

        assertEq(core.lockLevel(), 0);
        assertTrue(!core.isLocked());
        assertTrue(core.isUnlocked());
        assertEq(core.lastSender(), addresses.governorAddress);

        vm.roll(block.number + 1);
        vm.expectRevert("GlobalReentrancyLock: not entered this block");
        core.unlock(2);

        vm.stopPrank();
    }

    /// ---------- ACL Tests ----------

    function testUnlockFailsNonStateRole() public {
        vm.expectRevert("GlobalReentrancyLock: missing locker role");
        core.unlock(1);
    }

    function testLockFailsNonStateRole() public {
        vm.expectRevert("GlobalReentrancyLock: missing locker role");
        core.lock(1);
    }

    function testGovernorSystemRecoveryFailsNotGovernor() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.governanceEmergencyRecover();
    }

    function testGovernorEmergencyPauseFailsNotGovernor() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.governanceEmergencyPause();
    }
}
