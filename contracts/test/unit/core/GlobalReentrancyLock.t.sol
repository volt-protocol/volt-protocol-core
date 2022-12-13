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
import {getCoreV2} from "./../utils/Fixtures.sol";
import {VoltRoles} from "../../../core/VoltRoles.sol";
import {MockERC20} from "./../../../mock/MockERC20.sol";
import {MockReentrancyLock} from "./../../../mock/MockReentrancyLock.sol";
import {MockReentrancyLockFailure} from "./../../../mock/MockReentrancyLockFailure.sol";
import {TestAddresses as addresses} from "../utils/TestAddresses.sol";
import {IGlobalReentrancyLock, GlobalReentrancyLock} from "./../../../core/GlobalReentrancyLock.sol";

contract UnitTestGlobalReentrancyLock is DSTest {
    /// @notice emitted when governor does an emergency lock
    event EmergencyLock(address indexed sender, uint256 timestamp);

    CoreV2 private core;

    Vm public constant vm = Vm(HEVM_ADDRESS);
    MockERC20 volt;
    MockReentrancyLock private testLock;
    Vcon vcon;
    GlobalReentrancyLock lock;

    function setUp() public {
        volt = new MockERC20();

        // Deploy Core from Governor address
        vm.startPrank(addresses.governorAddress);
        core = new CoreV2(address(volt));
        vcon = new Vcon(addresses.governorAddress, addresses.governorAddress);
        testLock = new MockReentrancyLock(address(core));
        core.grantLocker(address(testLock));
        lock = new GlobalReentrancyLock(address(core));
        core.setGlobalReentrancyLock(IGlobalReentrancyLock(address(lock)));

        vm.stopPrank();
    }

    function testSetup() public {
        assertEq(address(core.volt()), address(volt));
        assertEq(address(core.vcon()), address(0)); /// vcon starts set to address 0

        assertTrue(core.isGovernor(address(core))); /// core contract is governor
        assertTrue(core.isGovernor(addresses.governorAddress)); /// msg.sender of contract is governor

        assertTrue(lock.isUnlocked()); /// core starts out unlocked
        assertTrue(!lock.isLocked()); /// core starts out not locked
        assertEq(lock.lastSender(), address(0));
        assertEq(lock.lastBlockEntered(), 0);

        assertTrue(core.isLocker(address(testLock)));
    }

    function testLockFailsWithoutRole() public {
        vm.prank(addresses.governorAddress);
        core.revokeRole(VoltRoles.LOCKER, address(testLock));
        assertTrue(!core.isLocker(address(testLock)));

        vm.expectRevert("UNAUTHORIZED");
        testLock.testGlobalLock();

        assertTrue(lock.isUnlocked());
        assertTrue(!lock.isLocked());
    }

    function testLockFailsWithoutRoleRevokeGlobalLocker() public {
        vm.prank(addresses.governorAddress);
        core.revokeLocker(address(testLock));
        assertTrue(!core.isLocker(address(testLock)));

        vm.expectRevert("UNAUTHORIZED");
        testLock.testGlobalLock();

        assertTrue(lock.isUnlocked());
        assertTrue(!lock.isLocked());
    }

    function testLockSucceedsWithRole(uint8 numRuns) public {
        for (uint256 i = 0; i < numRuns; i++) {
            assertTrue(lock.isUnlocked());
            assertTrue(!lock.isLocked());
            assertEq(testLock.lastBlockNumber(), lock.lastBlockEntered());

            testLock.testGlobalLock();

            assertTrue(lock.isUnlocked());
            assertTrue(!lock.isLocked());
            assertEq(lock.lockLevel(), 0);
            assertEq(testLock.lastBlockNumber(), lock.lastBlockEntered());
            assertEq(lock.lastSender(), address(testLock));
        }
    }

    function testLockSucceedsWithRole(
        uint8 numRuns,
        address[8] memory lockers
    ) public {
        for (uint256 i = 0; i < numRuns; i++) {
            assertTrue(lock.isUnlocked());
            assertTrue(!lock.isLocked());

            address toPrank = lockers[i > 7 ? 7 : i];
            if (!core.isLocker(toPrank)) {
                vm.prank(addresses.governorAddress);
                core.grantLocker(toPrank);
            }

            vm.prank(toPrank);
            lock.lock(1);

            assertTrue(lock.isLocked());
            assertTrue(!lock.isUnlocked());
            assertEq(lock.lockLevel(), 1);
            assertEq(lock.lastBlockEntered(), block.number);
            assertEq(toPrank, lock.lastSender());

            vm.prank(toPrank);
            lock.unlock(0);

            assertEq(lock.lockLevel(), 0);
            assertTrue(lock.isUnlocked());
            assertTrue(!lock.isLocked());
            assertEq(toPrank, lock.lastSender());

            vm.roll(block.number + 1);
        }
    }

    function testLockLevel2SucceedsWithRole(
        uint8 numRuns,
        address[8] memory lockers
    ) public {
        for (uint256 i = 0; i < numRuns; i++) {
            assertTrue(lock.isUnlocked());
            assertTrue(!lock.isLocked());

            address toPrank = lockers[i > 7 ? 7 : i];
            if (!core.isLocker(toPrank)) {
                vm.prank(addresses.governorAddress);
                core.grantLocker(toPrank);
            }

            vm.startPrank(toPrank);

            lock.lock(1);
            lock.lock(2);

            assertEq(lock.lockLevel(), 2);
            assertEq(lock.lastBlockEntered(), block.number);
            assertEq(toPrank, lock.lastSender());

            lock.unlock(1);
            lock.unlock(0);

            vm.stopPrank();

            assertEq(lock.lockLevel(), 0);
            assertTrue(lock.isUnlocked());
            assertTrue(!lock.isLocked());
            assertEq(toPrank, lock.lastSender());
            vm.roll(block.number + 1);
        }
    }

    function testLockLevel1And2SucceedsWithRole(
        uint8 numRuns,
        address[8] memory lockers
    ) public {
        /// level
        for (uint256 i = 0; i < numRuns; i++) {
            assertTrue(lock.isUnlocked());
            assertTrue(!lock.isLocked());
            assertEq(lock.lockLevel(), 0);

            address toPrank = lockers[i > 7 ? 7 : i];
            if (!core.isLocker(toPrank)) {
                vm.prank(addresses.governorAddress);
                core.grantLocker(toPrank);
            }

            vm.prank(toPrank);
            lock.lock(1);

            assertEq(lock.lockLevel(), 1);
            assertEq(lock.lastBlockEntered(), block.number);
            assertEq(toPrank, lock.lastSender());

            if (!core.isLocker(toPrank)) {
                vm.prank(addresses.governorAddress);
                core.grantLocker(toPrank);
            }

            vm.prank(toPrank);
            lock.lock(2);

            assertTrue(lock.isLocked());
            assertEq(lock.lockLevel(), 2);

            assertEq(lock.lastBlockEntered(), block.number);
            assertEq(toPrank, lock.lastSender());

            vm.prank(toPrank);
            lock.unlock(1);

            assertEq(lock.lockLevel(), 1);
            assertTrue(!lock.isUnlocked());
            assertTrue(lock.isLocked());
            assertEq(toPrank, lock.lastSender());

            assertEq(toPrank, lock.lastSender());
            vm.prank(toPrank);
            lock.unlock(0);

            assertTrue(!lock.isLocked());
            assertEq(lock.lockLevel(), 0);
            assertTrue(lock.isUnlocked()); /// core is fully unlocked
            assertEq(toPrank, lock.lastSender());

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
            address(testLock)
        );
        vm.prank(addresses.governorAddress);
        core.grantLocker(address(lock2));

        /// CoreRef modifier globalLock enforces level
        vm.expectRevert("CoreRef: cannot lock less than current level");
        lock2.globalReentrancyFails();

        assertTrue(lock.isUnlocked());
        assertTrue(!lock.isLocked());
        assertEq(testLock.lastBlockNumber(), lock.lastBlockEntered());
    }

    function testGovernorSystemRecoveryFailsNotEntered() public {
        vm.prank(addresses.governorAddress);
        vm.expectRevert(
            "GlobalReentrancyLock: governor recovery, system not entered"
        );
        lock.governanceEmergencyRecover();
    }

    function testGovernorEmergencyPauseSucceeds() public {
        vm.expectEmit(true, false, false, true, address(lock));
        emit EmergencyLock(addresses.governorAddress, block.timestamp);

        vm.prank(addresses.governorAddress);
        lock.governanceEmergencyPause();

        assertTrue(lock.isLocked());
        assertEq(lock.lockLevel(), 2);
    }

    function testGovernorEmergencyRecoversFromEmergencyPause() public {
        testGovernorEmergencyPauseSucceeds();

        vm.prank(addresses.governorAddress);
        lock.governanceEmergencyRecover();

        assertTrue(!lock.isLocked());
        assertEq(lock.lockLevel(), 0);
    }

    function testGovernorSystemRecovery() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);

        lock.lock(1);

        assertTrue(lock.isLocked());
        assertTrue(!lock.isUnlocked());
        assertEq(lock.lockLevel(), 1);
        assertEq(lock.lastBlockEntered(), block.number);

        vm.expectRevert(
            "GlobalReentrancyLock: cannot unlock in same block as lock"
        );
        lock.governanceEmergencyRecover();

        vm.roll(block.number + 1);
        lock.governanceEmergencyRecover();

        assertTrue(!lock.isLocked());
        assertTrue(lock.isUnlocked());
        assertTrue(lock.lastBlockEntered() != block.number);
        assertEq(lock.lockLevel(), 0);

        vm.stopPrank();
    }

    function testGovernorSystemRecoveryLevelTwoLocked() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);

        lock.lock(1);
        lock.lock(2);

        assertEq(lock.lockLevel(), 2);
        assertTrue(lock.isLocked());
        assertTrue(!lock.isUnlocked());
        assertEq(lock.lastBlockEntered(), block.number);

        vm.expectRevert(
            "GlobalReentrancyLock: cannot unlock in same block as lock"
        );
        lock.governanceEmergencyRecover();

        vm.roll(block.number + 1);
        lock.governanceEmergencyRecover();

        assertTrue(!lock.isLocked());
        assertTrue(lock.isUnlocked());
        assertEq(lock.lockLevel(), 0);
        assertTrue(lock.lastBlockEntered() != block.number);

        vm.stopPrank();
    }

    function testGovernorSystemRecoveryLevelTwoAndLevelOneLocked() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);

        lock.lock(1);
        lock.lock(2);

        assertTrue(lock.isLocked());
        assertTrue(!lock.isUnlocked());

        assertEq(lock.lockLevel(), 2);
        assertEq(lock.lastBlockEntered(), block.number);

        vm.expectRevert(
            "GlobalReentrancyLock: cannot unlock in same block as lock"
        );
        lock.governanceEmergencyRecover();

        vm.roll(block.number + 1);
        lock.governanceEmergencyRecover();

        assertTrue(!lock.isLocked());
        assertTrue(lock.isUnlocked());
        assertEq(lock.lockLevel(), 0);
        assertTrue(lock.lastBlockEntered() != block.number);
        vm.stopPrank();
    }

    function testOnlySameLockerCanUnlock() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);

        lock.lock(1);
        core.grantLocker(address(this));

        vm.stopPrank();

        assertTrue(core.isLocker(address(this)));
        assertTrue(lock.isLocked());
        assertTrue(!lock.isUnlocked());
        assertEq(lock.lastBlockEntered(), block.number);
        assertEq(lock.lastSender(), addresses.governorAddress);

        vm.expectRevert("GlobalReentrancyLock: caller is not locker");
        lock.unlock(0);

        vm.prank(addresses.governorAddress);
        lock.unlock(0);

        assertTrue(!lock.isLocked());
        assertTrue(lock.isUnlocked());
        assertTrue(lock.lastBlockEntered() == block.number);
        assertEq(lock.lastSender(), addresses.governorAddress);
    }

    function testOnlySameLockerCanUnlockLevelTwo() public {
        vm.startPrank(addresses.governorAddress);

        core.grantLocker(addresses.governorAddress);

        lock.lock(1);
        lock.lock(2);

        vm.stopPrank();

        assertTrue(core.isLocker(addresses.governorAddress));

        assertEq(lock.lockLevel(), 2);

        assertTrue(lock.isLocked());
        assertTrue(!lock.isUnlocked());

        assertEq(lock.lastBlockEntered(), block.number);
        assertEq(lock.lastSender(), addresses.governorAddress);

        vm.expectRevert("UNAUTHORIZED");
        lock.unlock(0);
    }

    function testInvalidStateReverts() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);
        core.grantLocker(address(this));

        lock.lock(1);
        lock.lock(2);
        vm.stopPrank();

        assertTrue(core.isLocker(addresses.governorAddress));
        assertTrue(core.isLocker(address(this)));

        assertEq(lock.lockLevel(), 2);

        assertTrue(lock.isLocked());
        assertTrue(!lock.isUnlocked());

        assertEq(lock.lastBlockEntered(), block.number);
        assertEq(lock.lastSender(), addresses.governorAddress);

        vm.expectRevert("GlobalReentrancyLock: unlock level must be 1 lower");
        lock.unlock(0);
    }

    function testLockingLevelTwoWhileLevelOneLockedDoesntSetSender() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);
        core.grantLocker(address(this));

        lock.lock(1);
        assertEq(lock.lockLevel(), 1);
        vm.stopPrank();

        lock.lock(2);

        assertEq(lock.lockLevel(), 2);

        assertTrue(lock.isLocked());
        assertTrue(!lock.isUnlocked());

        assertEq(lock.lastBlockEntered(), block.number);
        assertEq(lock.lastSender(), addresses.governorAddress);
    }

    function testUnlockingLevelOneWhileLevelTwoLockedFails() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(address(this));
        core.grantLocker(address(this));
        vm.stopPrank();

        lock.lock(1);
        assertEq(lock.lockLevel(), 1);
        lock.lock(2);
        assertEq(lock.lockLevel(), 2);

        vm.expectRevert("GlobalReentrancyLock: unlock level must be 1 lower");
        lock.unlock(0);

        assertEq(lock.lockLevel(), 2);
        assertTrue(lock.isLocked());
        assertTrue(!lock.isUnlocked());
        assertEq(lock.lastBlockEntered(), block.number);
        assertEq(lock.lastSender(), address(this));
    }

    function testCannotLockLevel2WhileLevelNotLocked() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);

        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        lock.lock(2);

        vm.stopPrank();

        assertTrue(!lock.isLocked());
        assertTrue(lock.isUnlocked());
    }

    function testCannotLockLevel2WhileLevel1LockedPreviousBlock() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);

        lock.lock(1);
        vm.roll(block.number + 1);
        vm.expectRevert("GlobalReentrancyLock: system not entered this block");
        lock.lock(2);

        assertTrue(lock.isLocked());
        assertTrue(!lock.isUnlocked());
        assertTrue(lock.lastBlockEntered() == block.number - 1);
        assertEq(lock.lastSender(), addresses.governorAddress);

        vm.stopPrank();
    }

    function testCannotLockLevel2WhileLevel2Locked() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);

        lock.lock(1);
        lock.lock(2);
        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        lock.lock(2);

        assertEq(lock.lockLevel(), 2);
        assertTrue(lock.isLocked());
        assertTrue(!lock.isUnlocked());
        assertTrue(lock.lastBlockEntered() == block.number);
        assertEq(lock.lastSender(), addresses.governorAddress);

        vm.stopPrank();
    }

    function testCannotLockLevel3() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);

        lock.lock(1);
        lock.lock(2);
        vm.expectRevert("GlobalReentrancyLock: exceeds lock state");
        lock.lock(3);

        assertEq(lock.lockLevel(), 2);
        assertTrue(lock.isLocked());
        assertTrue(!lock.isUnlocked());
        assertEq(lock.lastSender(), addresses.governorAddress);

        vm.stopPrank();
    }

    function testUnlockFailsSystemNotEntered() public {
        vm.startPrank(addresses.governorAddress);

        core.grantLocker(addresses.governorAddress);
        lock.lock(1);
        lock.unlock(0);
        vm.expectRevert("GlobalReentrancyLock: system not entered");
        lock.unlock(1);
        vm.roll(block.number + 1);
        vm.expectRevert("GlobalReentrancyLock: not entered this block");
        lock.unlock(0);

        vm.stopPrank();
    }

    function testUnlockFailsSystemNotEnteredBlockAdvanced() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);
        lock.lock(1);
        lock.unlock(0);
        vm.roll(block.number + 1);
        vm.expectRevert("GlobalReentrancyLock: not entered this block");
        lock.unlock(0);
    }

    function testUnlockLevelTwoFailsSystemEnteredLevelOne() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);
        core.grantLocker(addresses.governorAddress);
        lock.lock(1);
        vm.expectRevert("GlobalReentrancyLock: unlock level must be 1 lower");
        lock.unlock(2);
        vm.expectRevert("GlobalReentrancyLock: unlock level must be 1 lower");
        lock.unlock(1);
        vm.stopPrank();
    }

    function testUnlockLevel2FailsSystemNotEnteredBlockAdvanced() public {
        vm.startPrank(addresses.governorAddress);

        core.grantLocker(addresses.governorAddress);
        lock.lock(1);
        lock.lock(2);

        assertEq(lock.lockLevel(), 2);
        assertTrue(lock.isLocked());
        assertTrue(!lock.isUnlocked());
        assertEq(lock.lastSender(), addresses.governorAddress);

        lock.unlock(1);
        lock.unlock(0);

        assertEq(lock.lockLevel(), 0);
        assertTrue(!lock.isLocked());
        assertTrue(lock.isUnlocked());
        assertEq(lock.lastSender(), addresses.governorAddress);

        vm.roll(block.number + 1);
        vm.expectRevert("GlobalReentrancyLock: not entered this block");
        lock.unlock(2);

        vm.stopPrank();
    }

    /// ---------- ACL Tests ----------

    function testUnlockFailsNonStateRole() public {
        vm.expectRevert("UNAUTHORIZED");
        lock.unlock(1);
    }

    function testLockFailsNonStateRole() public {
        vm.expectRevert("UNAUTHORIZED");
        lock.lock(1);
    }

    function testGovernorSystemRecoveryFailsNotGovernor() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        lock.governanceEmergencyRecover();
    }

    function testGovernorEmergencyPauseFailsNotGovernor() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        lock.governanceEmergencyPause();
    }
}
