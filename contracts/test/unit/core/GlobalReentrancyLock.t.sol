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
        core.grantGlobalLocker(address(lock));

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

        assertTrue(core.isGlobalLocker(address(lock)));
    }

    function testLockFailsWithoutRole() public {
        vm.prank(addresses.governorAddress);
        core.revokeRole(VoltRoles.GLOBAL_LOCKER_ROLE, address(lock));
        assertTrue(!core.isGlobalLocker(address(lock)));

        vm.expectRevert(
            "GlobalReentrancyLock: address missing global locker role"
        );
        lock.globalLock();

        assertTrue(core.isUnlocked()); /// core is still unlocked
        assertTrue(!core.isLocked()); /// core is still not locked
    }

    function testLockFailsWithoutRoleRevokeGlobalLocker() public {
        vm.prank(addresses.governorAddress);
        core.revokeGlobalLocker(address(lock));
        assertTrue(!core.isGlobalLocker(address(lock)));

        vm.expectRevert(
            "GlobalReentrancyLock: address missing global locker role"
        );
        lock.globalLock();

        assertTrue(core.isUnlocked()); /// core is still unlocked
        assertTrue(!core.isLocked()); /// core is still not locked
    }

    function testLockSucceedsWithRole(uint8 numRuns) public {
        for (uint256 i = 0; i < numRuns; i++) {
            assertTrue(core.isUnlocked()); /// core is still unlocked
            assertTrue(!core.isLocked()); /// core is still not locked
            assertEq(lock.lastBlockNumber(), core.lastBlockEntered());

            lock.globalLock();

            assertTrue(core.isUnlocked()); /// core is still unlocked
            assertTrue(!core.isLocked()); /// core is still not locked
            assertEq(lock.lastBlockNumber(), core.lastBlockEntered());
            assertEq(core.lastSender(), address(lock));
        }
    }

    function testLockSucceedsWithRole(uint8 numRuns, address[8] memory lockers)
        public
    {
        for (uint256 i = 0; i < numRuns; i++) {
            assertTrue(core.isUnlocked()); /// core is still unlocked
            assertTrue(!core.isLocked()); /// core is still not locked

            address toPrank = lockers[i > 7 ? 7 : i];
            if (!core.isGlobalLocker(toPrank)) {
                vm.prank(addresses.governorAddress);
                core.grantGlobalLocker(toPrank);
            }

            vm.prank(toPrank);
            core.lock();
            assertTrue(core.isLocked()); /// core is locked
            assertTrue(!core.isUnlocked()); /// core is locked
            assertEq(toPrank, core.lastSender());
            vm.prank(toPrank);
            core.unlock();

            assertTrue(core.isUnlocked()); /// core is still unlocked
            assertTrue(!core.isLocked()); /// core is still not locked
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
        core.grantGlobalLocker(address(lock2));

        vm.expectRevert("GlobalReentrancyLock: system already entered");
        lock2.globalReentrancyFails();

        assertTrue(core.isUnlocked()); /// core is still unlocked
        assertTrue(!core.isLocked()); /// core is still not locked
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
        core.grantGlobalLocker(addresses.governorAddress);

        core.lock();

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
        assertTrue(core.lastBlockEntered() != block.number);
        vm.stopPrank();
    }

    function testOnlySameLockerCanUnlock() public {
        vm.startPrank(addresses.governorAddress);
        core.grantGlobalLocker(addresses.governorAddress);

        core.lock();
        core.grantGlobalLocker(address(this));

        vm.stopPrank();

        assertTrue(core.isGlobalLocker(address(this)));
        assertTrue(core.isLocked());
        assertTrue(!core.isUnlocked());
        assertEq(core.lastBlockEntered(), block.number);
        assertEq(core.lastSender(), addresses.governorAddress);

        vm.expectRevert("GlobalReentrancyLock: caller is not locker");
        core.unlock();

        vm.prank(addresses.governorAddress);
        core.unlock();

        assertTrue(!core.isLocked());
        assertTrue(core.isUnlocked());
        assertTrue(core.lastBlockEntered() == block.number);
        assertEq(core.lastSender(), addresses.governorAddress);
    }

    function testUnlockFailsSystemNotEntered() public {
        vm.startPrank(addresses.governorAddress);

        core.grantGlobalLocker(addresses.governorAddress);
        core.lock();
        core.unlock();
        vm.expectRevert("GlobalReentrancyLock: system not entered");
        core.unlock();
        vm.roll(block.number + 1);
        vm.expectRevert("GlobalReentrancyLock: not entered this block");
        core.unlock();

        vm.stopPrank();
    }

    function testUnlockFailsSystemNotEnteredBlockAdvanced() public {
        vm.startPrank(addresses.governorAddress);
        core.grantGlobalLocker(addresses.governorAddress);
        core.lock();
        core.unlock();
        vm.roll(block.number + 1);
        vm.expectRevert("GlobalReentrancyLock: not entered this block");
        core.unlock();
    }

    /// ---------- ACL Tests ----------

    function testUnlockFailsNonStateRole() public {
        vm.expectRevert(
            "GlobalReentrancyLock: address missing global locker role"
        );
        core.unlock();
    }

    function testLockFailsNonStateRole() public {
        vm.expectRevert(
            "GlobalReentrancyLock: address missing global locker role"
        );
        core.lock();
    }

    function testGovernorSystemRecoveryFailsNotGovernor() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.governanceEmergencyRecover();
    }
}
