// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Vm} from "./../utils/Vm.sol";
import {Volt} from "../../../volt/Volt.sol";
import {IVolt} from "../../../volt/Volt.sol";
import {ICore} from "../../../core/ICore.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {VoltRoles} from "../../../core/VoltRoles.sol";
import {MockERC20} from "./../../../mock/MockERC20.sol";
import {CoreV2, Vcon} from "../../../core/CoreV2.sol";
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
        core.grantRole(VoltRoles.SYSTEM_STATE_ROLE, address(lock));

        vm.stopPrank();
    }

    function testSetup() public {
        assertEq(address(core.volt()), address(volt));
        assertEq(address(core.vcon()), address(0)); /// vcon starts set to address 0

        assertTrue(core.isGovernor(address(core))); /// core contract is governor
        assertTrue(core.isGovernor(addresses.governorAddress)); /// msg.sender of contract is governor

        assertTrue(core.isUnlocked()); /// core starts out unlocked
        assertTrue(!core.isLocked()); /// core starts out not locked

        assertTrue(core.hasRole(VoltRoles.SYSTEM_STATE_ROLE, address(lock)));
    }

    function testLockFailsWithoutRole() public {
        vm.prank(addresses.governorAddress);
        core.revokeRole(VoltRoles.SYSTEM_STATE_ROLE, address(lock));
        assertTrue(!core.hasRole(VoltRoles.SYSTEM_STATE_ROLE, address(lock)));

        vm.expectRevert("GlobalReentrancyLock: address missing state role");
        lock.globalLock();

        assertTrue(core.isUnlocked()); /// core is still unlocked
        assertTrue(!core.isLocked()); /// core is still not locked
    }

    function testLockSucceedsWithRole() public {
        assertTrue(core.isUnlocked()); /// core is still unlocked
        assertTrue(!core.isLocked()); /// core is still not locked
        assertEq(lock.lastBlockNumber(), core.lastBlockEntered());

        lock.globalLock();

        assertTrue(core.isUnlocked()); /// core is still unlocked
        assertTrue(!core.isLocked()); /// core is still not locked
        assertEq(lock.lastBlockNumber(), core.lastBlockEntered());
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
        core.grantRole(VoltRoles.SYSTEM_STATE_ROLE, address(lock2));

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
        core.grantRole(VoltRoles.SYSTEM_STATE_ROLE, addresses.governorAddress);

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

    function testLockFailsNonStateRole() public {
        vm.expectRevert("GlobalReentrancyLock: address missing state role");
        core.lock();
    }

    function testUnlockFailsNonStateRole() public {
        vm.expectRevert("GlobalReentrancyLock: address missing state role");
        core.unlock();
    }

    function testGovernorSystemRecoveryFailsNotGovernor() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.governanceEmergencyRecover();
    }
}
