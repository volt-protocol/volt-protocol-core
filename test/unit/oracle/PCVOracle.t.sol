// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {stdError} from "@forge-std/StdError.sol";
import {console} from "@forge-std/console.sol";
import {Test} from "@forge-std/Test.sol";

import {CoreV2} from "@voltprotocol/core/CoreV2.sol";
import {PCVOracle} from "@voltprotocol/oracle/PCVOracle.sol";
import {IPCVOracle} from "@voltprotocol/oracle/IPCVOracle.sol";
import {MockERC20} from "@test/mock/MockERC20.sol";
import {VoltRoles} from "@voltprotocol/core/VoltRoles.sol";
import {getCoreV2} from "@test/unit/utils/Fixtures.sol";
import {MockOracle} from "@test/mock/MockOracle.sol";
import {SystemEntry} from "@voltprotocol/entry/SystemEntry.sol";
import {MockOracleV2} from "@test/mock/MockOracleV2.sol";
import {MockPCVDepositV3} from "@test/mock/MockPCVDepositV3.sol";
import {TestAddresses as addresses} from "@test/unit/utils/TestAddresses.sol";
import {IGlobalReentrancyLock, GlobalReentrancyLock} from "@voltprotocol/core/GlobalReentrancyLock.sol";

contract PCVOracleUnitTest is Test {
    using SafeCast for *;

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
    MockOracleV2 private oracle1;
    MockOracleV2 private oracle2;

    GlobalReentrancyLock public lock;

    // PCVOracle events
    event VenueOracleUpdated(
        address indexed venue,
        address indexed oldOracle,
        address indexed newOracle
    );
    event VenueAdded(address indexed venue, uint256 timestamp);
    event VenueRemoved(address indexed venue, uint256 timestamp);
    event PCVUpdated(
        address indexed venue,
        uint256 timestamp,
        int256 deltaBalance,
        int256 deltaProfit
    );

    function setUp() public {
        // volt system
        core = CoreV2(address(getCoreV2()));
        pcvOracle = new PCVOracle(address(core));
        entry = new SystemEntry(address(core));
        lock = new GlobalReentrancyLock(address(core));

        // mock utils
        oracle1 = new MockOracleV2();
        oracle2 = new MockOracleV2();
        token1 = new MockERC20();
        token2 = new MockERC20();
        deposit1 = new MockPCVDepositV3(address(core), address(token1));
        deposit2 = new MockPCVDepositV3(address(core), address(token2));

        // grant role
        vm.startPrank(addresses.governorAddress);
        core.setGlobalReentrancyLock(IGlobalReentrancyLock(address(lock)));
        core.grantLocker(address(entry));
        core.grantLocker(address(pcvOracle));
        core.grantLocker(address(deposit1));
        core.grantLocker(address(deposit2));
        core.setPCVOracle(IPCVOracle(address(pcvOracle)));

        core.createRole(VoltRoles.PCV_DEPOSIT, VoltRoles.GOVERNOR);
        core.grantRole(VoltRoles.PCV_DEPOSIT, address(deposit1));
        core.grantRole(VoltRoles.PCV_DEPOSIT, address(deposit2));

        oracle1.setValues(1e18, true);
        oracle2.setValues(1e18, true);

        // add venues
        address[] memory venues = new address[](2);
        venues[0] = address(deposit1);
        venues[1] = address(deposit2);
        address[] memory oracles = new address[](2);
        oracles[0] = address(oracle1);
        oracles[1] = address(oracle2);
        pcvOracle.addVenues(venues, oracles);

        vm.stopPrank();
    }

    function testSetup() public {
        assertEq(pcvOracle.getVenues().length, 2);
        assertEq(pcvOracle.getNumVenues(), 2);
        uint256 totalPcv = pcvOracle.getTotalPcv();
        assertEq(totalPcv, 0);
        assertEq(pcvOracle.lastRecordedTotalPcv(), 0);

        {
            (uint128 balance, int128 profit) = pcvOracle.venueRecord(
                address(deposit1)
            );
            assertEq(balance, 0);
            assertEq(profit, 0);
        }
        {
            (uint128 balance, int128 profit) = pcvOracle.venueRecord(
                address(deposit2)
            );
            assertEq(balance, 0);
            assertEq(profit, 0);
        }

        assertEq(pcvOracle.venueToOracle(address(deposit1)), address(oracle1));
        assertEq(pcvOracle.venueToOracle(address(deposit2)), address(oracle2));
    }

    function testDecimalNormalization() public {
        oracle1.setValues(1e12, true); /// only add 12 decimals on deposit, this means 6 are truncated from 18

        token1.mint(address(deposit1), 100e18);
        entry.deposit(address(deposit1));

        assertEq(pcvOracle.lastRecordedPCV(address(deposit1)), 100e12); /// with scale up
        assertEq(pcvOracle.lastRecordedPCVRaw(address(deposit1)), 100); /// remove scale up
    }

    // -------------------------------------------------
    // Venues management (add/remove/set oracle)
    // -------------------------------------------------

    function testSetVenueOracle() public {
        assertEq(pcvOracle.venueToOracle(address(deposit1)), address(oracle1));

        // make deposit1 non-empty
        token1.mint(address(deposit1), 100e18);
        entry.deposit(address(deposit1));

        // create new oracle
        MockOracleV2 newOracle = new MockOracleV2();
        newOracle.setValues(0.5e18, true);

        // check event
        vm.expectEmit(false, false, false, true, address(pcvOracle));
        emit VenueOracleUpdated(
            address(deposit1),
            address(oracle1),
            address(newOracle)
        );
        vm.expectEmit(false, false, false, true, address(pcvOracle));
        emit PCVUpdated(address(deposit1), block.timestamp, -50e18, -50e18);
        // set
        vm.prank(addresses.governorAddress);
        pcvOracle.setVenueOracle(address(deposit1), address(newOracle));

        assertEq(
            pcvOracle.venueToOracle(address(deposit1)),
            address(newOracle)
        );
    }

    function testSetVenueOracleRevertIfDepositDoesntExist() public {
        vm.prank(addresses.governorAddress);
        vm.expectRevert("PCVOracle: invalid venue");
        pcvOracle.setVenueOracle(address(10000), address(oracle1));
    }

    function testSetVenueOracleRevertIfOracleInvalid() public {
        // make deposit1 non-empty
        token1.mint(address(deposit1), 100e18);
        entry.deposit(address(deposit1));
        token2.mint(address(deposit2), 100e18);
        entry.deposit(address(deposit2));

        // create new oracle
        MockOracleV2 newOracle = new MockOracleV2();

        // revert case 1
        newOracle.setValues(1e18, true);
        oracle1.setValues(1e18, false);
        vm.prank(addresses.governorAddress);
        vm.expectRevert("PCVOracle: invalid old oracle");
        pcvOracle.setVenueOracle(address(deposit1), address(newOracle));

        // revert case 2
        newOracle.setValues(1e18, false);
        oracle1.setValues(1e18, true);
        vm.prank(addresses.governorAddress);
        vm.expectRevert("PCVOracle: invalid new oracle");
        pcvOracle.setVenueOracle(address(deposit1), address(newOracle));
    }

    function testAddVenues() public {
        uint256 currentTimestamp = 12345;
        vm.warp(currentTimestamp);

        address[] memory venues = new address[](2);
        venues[0] = address(deposit1);
        venues[1] = address(deposit2);
        address[] memory oracles = new address[](2);
        oracles[0] = address(oracle1);
        oracles[1] = address(oracle2);

        vm.prank(addresses.governorAddress);
        pcvOracle.removeVenues(venues);

        // pre-add check
        assertEq(pcvOracle.isVenue(address(deposit1)), false);
        assertEq(pcvOracle.isVenue(address(deposit2)), false);
        assertEq(pcvOracle.venueToOracle(address(deposit1)), address(0));
        assertEq(pcvOracle.venueToOracle(address(deposit2)), address(0));

        // check events
        vm.expectEmit(false, false, false, true, address(pcvOracle));
        emit VenueOracleUpdated(
            address(deposit1),
            address(0),
            address(oracle1)
        );
        vm.expectEmit(false, false, false, true, address(pcvOracle));
        emit VenueAdded(address(deposit1), currentTimestamp);
        vm.expectEmit(false, false, false, true, address(pcvOracle));
        emit VenueOracleUpdated(
            address(deposit2),
            address(0),
            address(oracle2)
        );
        vm.expectEmit(false, false, false, true, address(pcvOracle));
        emit VenueAdded(address(deposit2), currentTimestamp);
        // add
        vm.prank(addresses.governorAddress);
        pcvOracle.addVenues(venues, oracles);

        // post-add check
        assertEq(pcvOracle.getVenues().length, 2);
        assertEq(pcvOracle.isVenue(address(deposit1)), true);
        assertEq(pcvOracle.isVenue(address(deposit2)), true);
        assertEq(pcvOracle.venueToOracle(address(deposit1)), address(oracle1));
        assertEq(pcvOracle.venueToOracle(address(deposit1)), address(oracle1));
        assertEq(pcvOracle.getTotalPcv(), pcvOracle.lastRecordedTotalPcv());
    }

    function testRemoveVenues() public {
        uint256 currentTimestamp = 12345;
        vm.warp(currentTimestamp);

        address[] memory venues = new address[](2);
        venues[0] = address(deposit1);
        venues[1] = address(deposit2);
        address[] memory oracles = new address[](2);
        oracles[0] = address(oracle1);
        oracles[1] = address(oracle2);

        // pre-remove check
        assertEq(pcvOracle.isVenue(address(deposit1)), true);
        assertEq(pcvOracle.isVenue(address(deposit2)), true);
        assertEq(pcvOracle.venueToOracle(address(deposit1)), address(oracle1));
        assertEq(pcvOracle.venueToOracle(address(deposit2)), address(oracle2));

        // check events
        vm.expectEmit(false, false, false, true, address(pcvOracle));
        emit VenueOracleUpdated(
            address(deposit1),
            address(oracle1),
            address(0)
        );
        vm.expectEmit(false, false, false, true, address(pcvOracle));
        emit VenueRemoved(address(deposit1), currentTimestamp);
        vm.expectEmit(false, false, false, true, address(pcvOracle));
        emit VenueOracleUpdated(
            address(deposit2),
            address(oracle2),
            address(0)
        );
        vm.expectEmit(false, false, false, true, address(pcvOracle));
        emit VenueRemoved(address(deposit2), currentTimestamp);
        // remove
        vm.prank(addresses.governorAddress);
        pcvOracle.removeVenues(venues);

        // post-add check
        assertEq(pcvOracle.isVenue(address(deposit1)), false);
        assertEq(pcvOracle.isVenue(address(deposit2)), false);
        assertEq(pcvOracle.venueToOracle(address(deposit1)), address(0));
        assertEq(pcvOracle.venueToOracle(address(deposit2)), address(0));
    }

    function testAddNonEmptyVenuesRevertsIfOracleIsInvalid() public {
        uint256 currentTimestamp = 12345;
        vm.warp(currentTimestamp);

        // make deposit1 non-empty
        token1.mint(address(deposit1), 100e18);
        entry.deposit(address(deposit1));

        // prepare add
        address[] memory venues = new address[](1);
        venues[0] = address(deposit1);
        address[] memory oracles = new address[](1);
        oracles[0] = address(oracle1);

        vm.prank(addresses.governorAddress);
        pcvOracle.removeVenues(venues);

        // set invalid oracle
        oracle1.setValues(1e18, false);

        // add
        vm.prank(addresses.governorAddress);
        vm.expectRevert("PCVOracle: invalid oracle value");
        pcvOracle.addVenues(venues, oracles);
    }

    function testRemoveNonEmptyVenuesRevertsIfOracleIsInvalid() public {
        uint256 currentTimestamp = 12345;
        vm.warp(currentTimestamp);

        // make deposit1 non-empty
        token1.mint(address(deposit1), 100e18);
        entry.deposit(address(deposit1));

        {
            (uint128 balance, int128 profit) = pcvOracle.venueRecord(
                address(deposit1)
            );
            assertEq(balance, 100e18);
            assertEq(profit, 0);
        }

        {
            address[] memory venues = new address[](2);
            venues[0] = address(deposit1);
            venues[1] = address(deposit2);
            address[] memory oracles = new address[](2);
            oracles[0] = address(oracle1);
            oracles[1] = address(oracle2);

            vm.prank(addresses.governorAddress);
            pcvOracle.removeVenues(venues);
        }

        {
            // prepare add
            address[] memory venues = new address[](1);
            venues[0] = address(deposit1);
            address[] memory oracles = new address[](1);
            oracles[0] = address(oracle1);

            // add
            vm.prank(addresses.governorAddress);
            pcvOracle.addVenues(venues, oracles);

            // set invalid oracle
            oracle1.setValues(1e18, false);

            // remove
            vm.prank(addresses.governorAddress);
            vm.expectRevert("PCVOracle: invalid oracle value");
            pcvOracle.removeVenues(venues);
        }
    }

    // -------------------------------------------------
    // Accounting Checks
    // -------------------------------------------------

    function testTotalPcvNegativeReverts() public {
        vm.expectRevert("SafeCast: value must be positive");
        deposit1.setLastRecordedProfit(-1);
    }

    function testProfitTracking() public {
        int128 venue1Profit = 10e18;
        int128 venue2Profit = 20e18;

        deposit1.setLastRecordedProfit(venue1Profit);
        deposit2.setLastRecordedProfit(venue2Profit);

        {
            (uint128 balance, int128 profit) = pcvOracle.venueRecord(
                address(deposit1)
            );
            assertEq(balance, venue1Profit.toUint256());
            assertEq(profit, venue1Profit);
        }
        {
            (uint128 balance, int128 profit) = pcvOracle.venueRecord(
                address(deposit2)
            );
            assertEq(balance, venue2Profit.toUint256());
            assertEq(profit, venue2Profit);
        }

        assertEq(
            pcvOracle.lastRecordedTotalPcv(),
            uint256(uint128(venue1Profit + venue2Profit))
        ); /// profits are part of total PCV
    }

    function testGetVenueBalanceRevertsInvalidOracle() public {
        oracle1.setValues(oracle1.price(), false);
        vm.expectRevert("PCVOracle: invalid oracle value");
        pcvOracle.getVenueBalance(address(deposit1));
    }

    function testTrackDepositValueOnAddAndRemove() public {
        {
            address[] memory venues = new address[](1);
            venues[0] = address(deposit2);
            vm.prank(addresses.governorAddress);
            pcvOracle.removeVenues(venues);
        }

        // make deposit1 non-empty
        token1.mint(address(deposit1), 100e18);
        entry.deposit(address(deposit1));

        assertEq(pcvOracle.lastRecordedPCV(address(deposit1)), 100e18);
        assertEq(pcvOracle.lastRecordedPCVRaw(address(deposit1)), 100); /// remove scaling factor for raw value
        assertEq(
            pcvOracle.lastRecordedPCV(address(deposit1)),
            pcvOracle.getVenueBalance(address(deposit1))
        );
        assertEq(pcvOracle.lastRecordedProfit(address(deposit1)), 0);

        // check getPcv()
        uint256 totalPcv1 = pcvOracle.getTotalPcv();
        assertEq(totalPcv1, 100e18); // 100$ total

        {
            address[] memory venues = new address[](1);
            venues[0] = address(deposit1);
            // remove venue
            vm.prank(addresses.governorAddress);
            pcvOracle.removeVenues(venues);
        }

        assertEq(pcvOracle.lastRecordedPCV(address(deposit1)), 0);
        assertEq(pcvOracle.lastRecordedProfit(address(deposit1)), 0);

        vm.expectRevert("PCVOracle: invalid caller deposit");
        pcvOracle.getVenueBalance(address(deposit1));

        // check getPcv()
        uint256 totalPcv2 = pcvOracle.getTotalPcv();
        assertEq(totalPcv2, 0); // 0$ total
        assertEq(uint256(pcvOracle.lastRecordedTotalPcv()), totalPcv2);
    }

    function testAccountingOnHook() public {
        // set oracle values
        oracle1.setValues(1e18, true); // simulating "DAI" (1$ coin, 18 decimals)
        oracle2.setValues(1e18 * 1e12, true); // simulating "USDC" (1$ coin, 6 decimals)

        // make deposit1 non-empty
        token1.mint(address(deposit1), 100e18);
        entry.deposit(address(deposit1));

        // check getPcv()
        uint256 totalPcv1 = pcvOracle.getTotalPcv();
        assertEq(totalPcv1, 100e18); // 100$ total
        assertEq(uint256(pcvOracle.lastRecordedTotalPcv()), totalPcv1);

        // deposit 1 has 100$ + 300$
        token1.mint(address(deposit1), 300e18);
        entry.deposit(address(deposit1));
        // deposit 2 has 400$
        token2.mint(address(deposit2), 400e6);
        entry.deposit(address(deposit2));

        // check getPcv()
        uint256 totalPcv2 = pcvOracle.getTotalPcv();

        assertEq(totalPcv2, 800e18); // 800$ total
        assertEq(uint256(pcvOracle.lastRecordedTotalPcv()), totalPcv2);

        // A call from a PCVDeposit refreshes accounting
        vm.startPrank(address(deposit2));
        lock.lock(1);
        lock.lock(2);
        vm.expectEmit(true, false, false, true, address(pcvOracle));
        emit PCVUpdated(address(deposit2), block.timestamp, 400e18, 150e18);
        pcvOracle.updateBalance(int256(400e6), int256(150e6));
        vm.stopPrank();

        // A call from a PCVDeposit refreshes accounting
        vm.startPrank(address(deposit1));
        vm.expectEmit(true, false, false, true, address(pcvOracle));
        emit PCVUpdated(address(deposit1), block.timestamp, 300e18, 100e18);
        pcvOracle.updateBalance(int256(300e18), int256(100e18));
        vm.stopPrank();
    }

    function testGetPcvRevertIfOracleInvalid() public {
        // make deposit1 non-empty
        token1.mint(address(deposit1), 100e18);
        entry.deposit(address(deposit1));

        // set oracle values
        oracle1.setValues(123456, true); // oracle valid

        // set oracle values
        oracle1.setValues(123456, false); // oracle invalid
        oracle2.setValues(1e18, true);

        // getPcv() reverts because oracle is invalid
        vm.expectRevert("PCVOracle: invalid oracle value");
        pcvOracle.getTotalPcv();

        // set oracle values
        oracle1.setValues(1e18, true);
        oracle2.setValues(123456, false); // oracle invalid

        // getPcv() reverts because oracle is invalid
        vm.expectRevert("PCVOracle: invalid oracle value");
        pcvOracle.getTotalPcv();
    }

    function testPcvHookFailsInvalidOracleValue() public {
        // set oracle values
        oracle1.setValues(123456, false); // oracle invalid

        vm.startPrank(address(deposit1));

        lock.lock(1);
        lock.lock(2);

        // getPcv() reverts because oracle is invalid
        vm.expectRevert("PCVOracle: invalid oracle value");
        pcvOracle.updateBalance(0, 0); /// 0 delta balance or profit

        vm.stopPrank();
    }

    // ---------------- Access Control -----------------

    function testSetVenueOracleAcl() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        pcvOracle.setVenueOracle(address(deposit1), address(oracle1));
    }

    function testAddVenuesAcl() public {
        address[] memory venues = new address[](1);
        address[] memory oracles = new address[](1);

        vm.expectRevert("CoreRef: Caller is not a governor");
        pcvOracle.addVenues(venues, oracles);
    }

    function testRemoveVenuesAcl() public {
        address[] memory venues = new address[](1);

        vm.expectRevert("CoreRef: Caller is not a governor");
        pcvOracle.removeVenues(venues);
    }

    function testUpdateBalanceAcl() public {
        vm.expectRevert("UNAUTHORIZED");
        pcvOracle.updateBalance(0.5e18, 0);
    }

    function testUpdateBalanceUnconfiguredDeposit() public {
        MockPCVDepositV3 newDeposit = new MockPCVDepositV3(
            address(core),
            address(token1)
        );
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(address(newDeposit));
        core.createRole(VoltRoles.PCV_DEPOSIT, VoltRoles.GOVERNOR);
        core.grantRole(VoltRoles.PCV_DEPOSIT, address(newDeposit));
        vm.stopPrank();

        // reverts because we need to call addVenue before otherwise
        // even if the PCVDeposit has the proper roles, it doesn't have
        // an oracle configured.
        vm.startPrank(address(newDeposit));

        lock.lock(1);
        vm.expectRevert("CoreRef: System not at lock level");
        pcvOracle.updateBalance(1e18, 0);

        lock.lock(2);
        vm.expectRevert("PCVOracle: invalid caller deposit");
        pcvOracle.updateBalance(1e18, 0);

        vm.stopPrank();
    }
}
