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
import {getCoreV2, getAddresses, VoltTestAddresses} from "./../utils/Fixtures.sol";

contract UnitTestGlobalReentrancyLock is DSTest {
    CoreV2 private core;

    Vm public constant vm = Vm(HEVM_ADDRESS);
    VoltTestAddresses public addresses = getAddresses();
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
        core.grantLevelOneLocker(address(lock));

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

        assertTrue(core.isLevelOneLocker(address(lock)));
    }

    function testLockFailsWithoutRole() public {
        vm.prank(addresses.governorAddress);
        core.revokeRole(VoltRoles.LEVEL_ONE_LOCKER_ROLE, address(lock));
        assertTrue(!core.isLevelOneLocker(address(lock)));

        vm.expectRevert(
            "GlobalReentrancyLock: address missing global locker level one role"
        );
        lock.globalLock();

        assertTrue(core.isUnlocked());
        assertTrue(!core.isLocked());
    }

    function testLockFailsWithoutRoleRevokeGlobalLocker() public {
        vm.prank(addresses.governorAddress);
        core.revokeLevelOneLocker(address(lock));
        assertTrue(!core.isLevelOneLocker(address(lock)));

        vm.expectRevert(
            "GlobalReentrancyLock: address missing global locker level one role"
        );
        lock.globalLock();

        assertTrue(core.isUnlocked());
        assertTrue(!core.isLocked());
    }

    function testLockSucceedsWithRole(uint8 numRuns) public {
        for (uint256 i = 0; i < numRuns; i++) {
            assertTrue(core.isUnlocked());
            assertTrue(!core.isLocked());
            assertEq(lock.lastBlockNumber(), core.lastBlockEntered());

            lock.globalLock();

            assertTrue(core.isUnlocked());
            assertTrue(!core.isLocked());
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
            if (!core.isLevelOneLocker(toPrank)) {
                vm.prank(addresses.governorAddress);
                core.grantLevelOneLocker(toPrank);
            }

            vm.prank(toPrank);
            core.lockLevelOne();
            assertTrue(core.isLockedLevelOne());
            assertTrue(!core.isUnlockedLevelOne());

            assertTrue(!core.isLockedLevelTwo());
            assertTrue(core.isUnlockedLevelTwo());
            assertEq(core.lastBlockEntered(), block.number);

            assertEq(toPrank, core.lastSender());
            vm.prank(toPrank);
            core.unlockLevelOne();

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
            if (!core.isLevelTwoLocker(toPrank)) {
                vm.prank(addresses.governorAddress);
                core.grantLevelTwoLocker(toPrank);
            }

            vm.prank(toPrank);
            core.lockLevelTwo();
            assertTrue(core.isLockedLevelOne());
            assertTrue(!core.isUnlockedLevelOne());

            assertTrue(core.isLockedLevelTwo());
            assertTrue(!core.isUnlockedLevelTwo());
            assertEq(core.lastBlockEntered(), block.number);

            assertEq(toPrank, core.lastSender());
            vm.prank(toPrank);
            core.unlockLevelTwo();

            assertTrue(!core.isLockedLevelTwo());
            assertTrue(core.isUnlockedLevelTwo());
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

            address toPrank = lockers[i > 7 ? 7 : i];
            if (!core.isLevelOneLocker(toPrank)) {
                vm.prank(addresses.governorAddress);
                core.grantLevelOneLocker(toPrank);
            }

            vm.prank(toPrank);
            core.lockLevelOne();
            assertTrue(core.isLockedLevelOne());
            assertTrue(!core.isUnlockedLevelOne());

            assertTrue(!core.isLockedLevelTwo());
            assertTrue(core.isUnlockedLevelTwo());
            assertEq(core.lastBlockEntered(), block.number);

            if (!core.isLevelTwoLocker(toPrank)) {
                vm.prank(addresses.governorAddress);
                core.grantLevelTwoLocker(toPrank);
            }

            vm.prank(toPrank);
            core.lockLevelTwo();

            assertTrue(core.isLockedLevelOne());
            assertTrue(core.isLockedLevelTwo());

            assertTrue(!core.isUnlockedLevelOne());
            assertTrue(!core.isUnlockedLevelTwo());

            assertEq(core.lastBlockEntered(), block.number);
            assertEq(toPrank, core.lastSender());

            vm.prank(toPrank);
            core.unlockLevelTwo();

            assertTrue(!core.isLockedLevelTwo());
            assertTrue(core.isUnlockedLevelTwo());
            assertTrue(!core.isUnlockedLevelOne());
            assertTrue(!core.isUnlocked());
            assertTrue(core.isLocked());
            assertEq(toPrank, core.lastSender());

            assertEq(toPrank, core.lastSender());
            vm.prank(toPrank);
            core.unlockLevelOne();

            assertTrue(core.isUnlocked()); /// core is fully unlocked
            assertTrue(!core.isLocked());
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
        core.grantLevelOneLocker(address(lock2));

        vm.expectRevert("GlobalReentrancyLock: system locked level 1");
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

    function testGovernorSystemRecovery() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLevelOneLocker(addresses.governorAddress);

        core.lockLevelOne();

        assertTrue(core.isUnlockedLevelTwo());
        assertTrue(!core.isLockedLevelTwo());
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
        assertTrue(core.isUnlockedLevelOne());
        assertTrue(core.isUnlockedLevelTwo());
        assertTrue(core.lastBlockEntered() != block.number);
        vm.stopPrank();
    }

    function testGovernorSystemRecoveryLevelTwoLocked() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLevelTwoLocker(addresses.governorAddress);

        core.lockLevelTwo();

        assertTrue(!core.isUnlockedLevelTwo());
        assertTrue(core.isLockedLevelTwo());
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
        assertTrue(core.isUnlockedLevelOne());
        assertTrue(core.isUnlockedLevelTwo());
        assertTrue(core.lastBlockEntered() != block.number);
        vm.stopPrank();
    }

    function testGovernorSystemRecoveryLevelTwoAndLevelOneLocked() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLevelOneLocker(addresses.governorAddress);
        core.grantLevelTwoLocker(addresses.governorAddress);

        core.lockLevelOne();
        core.lockLevelTwo();

        assertTrue(core.isLocked());
        assertTrue(core.isLockedLevelTwo());

        assertTrue(!core.isUnlocked());
        assertTrue(!core.isUnlockedLevelTwo());

        assertEq(core.lastBlockEntered(), block.number);

        vm.expectRevert(
            "GlobalReentrancyLock: cannot unlock in same block as lock"
        );
        core.governanceEmergencyRecover();

        vm.roll(block.number + 1);
        core.governanceEmergencyRecover();

        assertTrue(!core.isLocked());
        assertTrue(core.isUnlocked());
        assertTrue(core.isUnlockedLevelOne());
        assertTrue(core.isUnlockedLevelTwo());
        assertTrue(core.lastBlockEntered() != block.number);
        vm.stopPrank();
    }

    function testOnlySameLockerCanUnlock() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLevelOneLocker(addresses.governorAddress);

        core.lockLevelOne();
        core.grantLevelOneLocker(address(this));

        vm.stopPrank();

        assertTrue(core.isLevelOneLocker(address(this)));
        assertTrue(core.isLocked());
        assertTrue(!core.isUnlocked());
        assertEq(core.lastBlockEntered(), block.number);
        assertEq(core.lastSender(), addresses.governorAddress);

        vm.expectRevert("GlobalReentrancyLock: caller is not locker");
        core.unlockLevelOne();

        vm.prank(addresses.governorAddress);
        core.unlockLevelOne();

        assertTrue(!core.isLocked());
        assertTrue(core.isUnlocked());
        assertTrue(core.lastBlockEntered() == block.number);
        assertEq(core.lastSender(), addresses.governorAddress);
    }

    function testOnlySameLockerCanUnlockLevelTwo() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLevelTwoLocker(addresses.governorAddress);
        core.grantLevelTwoLocker(address(this));

        core.lockLevelTwo();
        vm.stopPrank();

        assertTrue(core.isLevelTwoLocker(addresses.governorAddress));
        assertTrue(core.isLevelTwoLocker(address(this)));

        assertTrue(!core.isUnlockedLevelTwo());
        assertTrue(core.isLockedLevelTwo());

        assertTrue(core.isLocked());
        assertTrue(!core.isUnlocked());

        assertEq(core.lastBlockEntered(), block.number);
        assertEq(core.lastSender(), addresses.governorAddress);

        vm.expectRevert("GlobalReentrancyLock: caller is not level 2 locker");
        core.unlockLevelTwo();
    }

    function testLockingLevelTwoWhileLevelOneLockedDoesntSetSender() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLevelOneLocker(addresses.governorAddress);
        core.grantLevelTwoLocker(address(this));

        core.lockLevelOne();
        vm.stopPrank();

        core.lockLevelTwo();

        assertTrue(!core.isUnlockedLevelTwo());
        assertTrue(core.isLockedLevelTwo());

        assertTrue(core.isLocked());
        assertTrue(!core.isUnlocked());

        assertEq(core.lastBlockEntered(), block.number);
        assertEq(core.lastSender(), addresses.governorAddress);
    }

    function testUnlockingLevelOneWhileLevelTwoLockedFails() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLevelOneLocker(address(this));
        core.grantLevelTwoLocker(address(this));
        vm.stopPrank();

        core.lockLevelOne();
        core.lockLevelTwo();

        vm.expectRevert("GlobalReentrancyLock: system entered level 2");
        core.unlockLevelOne();

        assertTrue(core.isLocked());
        assertTrue(!core.isUnlocked());
        assertEq(core.lastBlockEntered(), block.number);
        assertEq(core.lastSender(), address(this));
    }

    function testCannotLockLevel1WhileLevel1Locked() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLevelOneLocker(addresses.governorAddress);
        core.grantLevelTwoLocker(addresses.governorAddress);

        core.lockLevelTwo();

        assertTrue(core.isLocked());
        assertTrue(!core.isUnlocked());
        assertTrue(core.lastBlockEntered() == block.number);
        assertEq(core.lastSender(), addresses.governorAddress);

        vm.expectRevert("GlobalReentrancyLock: system locked level 2");
        core.lockLevelOne();

        vm.stopPrank();
    }

    function testCannotLockLevel2WhileLevel1LockedPreviousBlock() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLevelOneLocker(addresses.governorAddress);
        core.grantLevelTwoLocker(addresses.governorAddress);

        core.lockLevelOne();
        vm.roll(block.number + 1);
        vm.expectRevert(
            "GlobalReentrancyLock: system not entered this block level 2"
        );
        core.lockLevelTwo();

        assertTrue(core.isLocked());
        assertTrue(!core.isUnlocked());
        assertTrue(core.lastBlockEntered() == block.number - 1);
        assertEq(core.lastSender(), addresses.governorAddress);

        vm.stopPrank();
    }

    function testCannotLockLevel2WhileLevel2Locked() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLevelTwoLocker(addresses.governorAddress);

        core.lockLevelTwo();
        vm.expectRevert("GlobalReentrancyLock: system already locked level 2");
        core.lockLevelTwo();

        assertTrue(core.isLocked());
        assertTrue(!core.isUnlocked());
        assertTrue(core.lastBlockEntered() == block.number);
        assertEq(core.lastSender(), addresses.governorAddress);

        vm.stopPrank();
    }

    function testUnlockFailsSystemNotEntered() public {
        vm.startPrank(addresses.governorAddress);

        core.grantLevelOneLocker(addresses.governorAddress);
        core.lockLevelOne();
        core.unlockLevelOne();
        vm.expectRevert("GlobalReentrancyLock: system not entered");
        core.unlockLevelOne();
        vm.roll(block.number + 1);
        vm.expectRevert("GlobalReentrancyLock: not entered this block");
        core.unlockLevelOne();

        vm.stopPrank();
    }

    function testUnlockFailsSystemNotEnteredBlockAdvanced() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLevelOneLocker(addresses.governorAddress);
        core.lockLevelOne();
        core.unlockLevelOne();
        vm.roll(block.number + 1);
        vm.expectRevert("GlobalReentrancyLock: not entered this block");
        core.unlockLevelOne();
    }

    function testUnlockLevelTwoFailsSystemEnteredLevelOne() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLevelOneLocker(addresses.governorAddress);
        core.grantLevelTwoLocker(addresses.governorAddress);
        core.lockLevelOne();
        vm.expectRevert("GlobalReentrancyLock: system not entered level 2");
        core.unlockLevelTwo();
        vm.stopPrank();
    }

    function testUnlockLevel2FailsSystemNotEnteredBlockAdvanced() public {
        vm.startPrank(addresses.governorAddress);
        core.grantLevelTwoLocker(addresses.governorAddress);
        core.lockLevelTwo();

        assertTrue(core.isLockedLevelTwo());
        assertTrue(!core.isUnlockedLevelTwo());

        core.unlockLevelTwo();

        assertTrue(!core.isLockedLevelTwo());
        assertTrue(core.isUnlockedLevelTwo());

        vm.roll(block.number + 1);
        vm.expectRevert("GlobalReentrancyLock: not entered this block");
        core.unlockLevelTwo();
    }

    /// ---------- ACL Tests ----------

    function testUnlockFailsNonStateRole() public {
        vm.expectRevert(
            "GlobalReentrancyLock: address missing global locker level one role"
        );
        core.unlockLevelOne();
    }

    function testLockFailsNonStateRole() public {
        vm.expectRevert(
            "GlobalReentrancyLock: address missing global locker level one role"
        );
        core.lockLevelOne();
    }

    function testUnlockLevelTwoFailsNonStateRole() public {
        vm.expectRevert(
            "GlobalReentrancyLock: address missing global locker level two role"
        );
        core.unlockLevelTwo();
    }

    function testLockLevelTwoFailsNonStateRole() public {
        vm.expectRevert(
            "GlobalReentrancyLock: address missing global locker level two role"
        );
        core.lockLevelTwo();
    }

    function testGovernorSystemRecoveryFailsNotGovernor() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.governanceEmergencyRecover();
    }
}
