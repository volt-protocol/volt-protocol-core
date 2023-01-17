// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Vm} from "@forge-std/Vm.sol";
import {Test} from "@forge-std/Test.sol";
import {CoreV2} from "../../../core/CoreV2.sol";
import {PCVOracle} from "../../../oracle/PCVOracle.sol";
import {IPCVOracle} from "../../../oracle/IPCVOracle.sol";
import {SystemEntry} from "../../../entry/SystemEntry.sol";
import {MockPCVDepositV3} from "../../../mock/MockPCVDepositV3.sol";
import {MockERC20} from "../../../mock/MockERC20.sol";
import {MockOracle} from "../../../mock/MockOracle.sol";
import {VoltRoles} from "../../../core/VoltRoles.sol";
import {getCoreV2} from "./../utils/Fixtures.sol";
import {TestAddresses as addresses} from "../utils/TestAddresses.sol";
import {IGlobalReentrancyLock, GlobalReentrancyLock} from "../../../core/GlobalReentrancyLock.sol";

contract SystemEntryUnitTest is Test {
    CoreV2 private core;
    SystemEntry public entry;

    // reference to the volt pcv oracle
    PCVOracle private pcvOracle;

    // test Tokens
    MockERC20 private token1;
    MockERC20 private token2;
    // test PCV Deposits
    MockPCVDepositV3 private deposit1;
    MockPCVDepositV3 private deposit2;
    // test Oracles
    MockOracle private oracle1;
    MockOracle private oracle2;
    IGlobalReentrancyLock private lock;

    // mocked DynamicVoltSystemOracle behavior to prevent reverts
    uint256 private liquidReserves;

    function updateActualRate(uint256 _liquidReserves) external {
        liquidReserves = _liquidReserves;
    }

    function setUp() public {
        // volt system
        core = CoreV2(address(getCoreV2()));
        pcvOracle = new PCVOracle(address(core));
        entry = new SystemEntry(address(core));
        lock = IGlobalReentrancyLock(
            address(new GlobalReentrancyLock(address(core)))
        );

        // mock utils
        oracle1 = new MockOracle();
        token1 = new MockERC20();
        deposit1 = new MockPCVDepositV3(address(core), address(token1));

        /// grant roles, set global reentrancy lock
        vm.startPrank(addresses.governorAddress);

        core.grantLocker(address(entry));
        core.grantLocker(address(pcvOracle));
        core.grantLocker(address(deposit1));

        core.setGlobalReentrancyLock(lock);

        vm.stopPrank();

        // setup pcv oracle
        address[] memory venues = new address[](1);
        venues[0] = address(deposit1);
        address[] memory oracles = new address[](1);
        oracles[0] = address(oracle1);
        vm.prank(addresses.governorAddress);
        pcvOracle.addVenues(venues, oracles);
        // setup pcv oracle
        vm.prank(addresses.governorAddress);
        core.setPCVOracle(IPCVOracle(address(pcvOracle)));
    }

    function testSetup() public {
        assertEq(address(entry.core()), address(core));
        assertTrue(!entry.paused());
    }

    // --------------- Happy paths --------------------------

    function testAccrue() public {
        vm.expectCall(address(deposit1), abi.encodeWithSignature("accrue()"));
        entry.accrue(address(deposit1));
    }

    function testDeposit() public {
        vm.expectCall(address(deposit1), abi.encodeWithSignature("deposit()"));
        entry.deposit(address(deposit1));
    }

    function testHarvest() public {
        vm.expectCall(address(deposit1), abi.encodeWithSignature("harvest()"));
        entry.harvest(address(deposit1));
    }

    // --------------- Paused state reverts -----------------

    function testAccrueRevertsIfPaused() public {
        vm.prank(addresses.governorAddress);
        entry.pause();

        vm.expectRevert("Pausable: paused");
        entry.accrue(address(deposit1));
    }

    function testDepositRevertsIfPaused() public {
        vm.prank(addresses.governorAddress);
        entry.pause();

        vm.expectRevert("Pausable: paused");
        entry.deposit(address(deposit1));
    }

    function testHarvestRevertsIfPaused() public {
        vm.prank(addresses.governorAddress);
        entry.pause();

        vm.expectRevert("Pausable: paused");
        entry.harvest(address(deposit1));
    }

    // --------------- Invalid deposit reverts --------------

    function testAccrueRevertsIfWrongDeposit() public {
        vm.expectRevert("SystemEntry: Invalid PCVDeposit");
        entry.accrue(address(this));
    }

    function testDepositRevertsIfWrongDeposit() public {
        vm.expectRevert("SystemEntry: Invalid PCVDeposit");
        entry.deposit(address(this));
    }

    function testHarvestRevertsIfWrongDeposit() public {
        vm.expectRevert("SystemEntry: Invalid PCVDeposit");
        entry.harvest(address(this));
    }
}
