// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Test} from "../../../../forge-std/src/Test.sol";
import {CoreV2} from "../../../core/CoreV2.sol";
import {PCVOracle} from "../../../oracle/PCVOracle.sol";
import {MockERC20} from "../../../mock/MockERC20.sol";
import {VoltRoles} from "../../../core/VoltRoles.sol";
import {getCoreV2} from "./../utils/Fixtures.sol";
import {MockOracle} from "../../../mock/MockOracle.sol";
import {SystemEntry} from "../../../entry/SystemEntry.sol";
import {MockOracleV2} from "../../../mock/MockOracleV2.sol";
import {MockPCVDepositV3} from "../../../mock/MockPCVDepositV3.sol";
import {TestAddresses as addresses} from "../utils/TestAddresses.sol";

contract PCVOracleUnitTest is Test {
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

    // PCVOracle events
    event VenueOracleUpdated(
        address indexed venue,
        address indexed oldOracle,
        address indexed newOracle
    );
    event VenueAdded(address indexed venue, bool isIliquid, uint256 timestamp);
    event VenueRemoved(
        address indexed venue,
        bool isIliquid,
        uint256 timestamp
    );
    event PCVUpdated(
        address indexed venue,
        bool isIliquid,
        uint256 timestamp,
        uint256 oldLiquidity,
        uint256 newLiquidity
    );
    event VoltSystemOracleUpdated(address oldOracle, address newOracle);

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

        // mock utils
        oracle1 = new MockOracleV2();
        oracle2 = new MockOracleV2();
        token1 = new MockERC20();
        token2 = new MockERC20();
        deposit1 = new MockPCVDepositV3(address(core), address(token1));
        deposit2 = new MockPCVDepositV3(address(core), address(token2));

        // grant role
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(address(entry));
        core.grantLocker(address(pcvOracle));
        core.grantLocker(address(deposit1));
        core.grantLocker(address(deposit2));
        vm.stopPrank();
    }

    function testSetup() public {
        assertEq(pcvOracle.voltOracle(), address(0));
        assertEq(pcvOracle.lastIlliquidBalance(), 0);
        assertEq(pcvOracle.lastLiquidBalance(), 0);
        assertEq(pcvOracle.getLiquidVenues().length, 0);
        assertEq(pcvOracle.getIlliquidVenues().length, 0);
        assertEq(pcvOracle.getAllVenues().length, 0);
        assertEq(pcvOracle.lastLiquidVenuePercentage(), 1e18);
        (uint256 liquidPcv, uint256 illiquidPcv, uint256 totalPcv) = pcvOracle
            .getTotalPcv();
        assertEq(liquidPcv, 0);
        assertEq(illiquidPcv, 0);
        assertEq(totalPcv, 0);
    }

    // -------------------------------------------------
    // Governor-only setup after deployment
    // -------------------------------------------------

    function testSetVoltOracle() public {
        assertEq(pcvOracle.voltOracle(), address(0));

        vm.prank(addresses.governorAddress);
        vm.expectEmit(false, false, false, true, address(pcvOracle));
        emit VoltSystemOracleUpdated(address(0), address(this));
        pcvOracle.setVoltOracle(address(this));

        assertEq(pcvOracle.voltOracle(), address(this));
    }

    // ---------------- Access Control -----------------

    function testSetVoltOracleAcl() public {
        vm.expectRevert(bytes("CoreRef: Caller is not a governor"));
        pcvOracle.setVoltOracle(address(this));
    }

    // -------------------------------------------------
    // Venues management (add/remove/set oracle)
    // -------------------------------------------------

    function testSetVenueOracle() public {
        assertEq(pcvOracle.venueToOracle(address(deposit1)), address(0));

        // check event
        vm.expectEmit(false, false, false, true, address(pcvOracle));
        emit VenueOracleUpdated(
            address(deposit1),
            address(0),
            address(oracle1)
        );
        // set
        vm.prank(addresses.governorAddress);
        pcvOracle.setVenueOracle(address(deposit1), address(oracle1));

        assertEq(pcvOracle.venueToOracle(address(deposit1)), address(oracle1));
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
        bool[] memory isLiquid = new bool[](2);
        isLiquid[0] = true;
        isLiquid[1] = false;

        // pre-add check
        assertEq(pcvOracle.isVenue(address(deposit1)), false);
        assertEq(pcvOracle.isLiquidVenue(address(deposit1)), false);
        assertEq(pcvOracle.isIlliquidVenue(address(deposit1)), false);
        assertEq(pcvOracle.isVenue(address(deposit2)), false);
        assertEq(pcvOracle.isLiquidVenue(address(deposit2)), false);
        assertEq(pcvOracle.isIlliquidVenue(address(deposit2)), false);
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
        emit VenueAdded(address(deposit1), true, currentTimestamp);
        vm.expectEmit(false, false, false, true, address(pcvOracle));
        emit VenueOracleUpdated(
            address(deposit2),
            address(0),
            address(oracle2)
        );
        vm.expectEmit(false, false, false, true, address(pcvOracle));
        emit VenueAdded(address(deposit2), false, currentTimestamp);
        // add
        vm.prank(addresses.governorAddress);
        pcvOracle.addVenues(venues, oracles, isLiquid);

        // post-add check
        assertEq(pcvOracle.isVenue(address(deposit1)), true);
        assertEq(pcvOracle.isLiquidVenue(address(deposit1)), true);
        assertEq(pcvOracle.isIlliquidVenue(address(deposit1)), false);
        assertEq(pcvOracle.isVenue(address(deposit2)), true);
        assertEq(pcvOracle.isLiquidVenue(address(deposit2)), false);
        assertEq(pcvOracle.isIlliquidVenue(address(deposit2)), true);
        assertEq(pcvOracle.venueToOracle(address(deposit1)), address(oracle1));
        assertEq(pcvOracle.venueToOracle(address(deposit2)), address(oracle2));
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
        bool[] memory isLiquid = new bool[](2);
        isLiquid[0] = true;
        isLiquid[1] = false;

        // add
        vm.prank(addresses.governorAddress);
        pcvOracle.addVenues(venues, oracles, isLiquid);

        // pre-remove check
        assertEq(pcvOracle.isVenue(address(deposit1)), true);
        assertEq(pcvOracle.isLiquidVenue(address(deposit1)), true);
        assertEq(pcvOracle.isIlliquidVenue(address(deposit1)), false);
        assertEq(pcvOracle.isVenue(address(deposit2)), true);
        assertEq(pcvOracle.isLiquidVenue(address(deposit2)), false);
        assertEq(pcvOracle.isIlliquidVenue(address(deposit2)), true);
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
        emit VenueRemoved(address(deposit1), true, currentTimestamp);
        vm.expectEmit(false, false, false, true, address(pcvOracle));
        emit VenueOracleUpdated(
            address(deposit2),
            address(oracle2),
            address(0)
        );
        vm.expectEmit(false, false, false, true, address(pcvOracle));
        emit VenueRemoved(address(deposit2), false, currentTimestamp);
        // remove
        vm.prank(addresses.governorAddress);
        pcvOracle.removeVenues(venues, isLiquid);

        // post-add check
        assertEq(pcvOracle.isVenue(address(deposit1)), false);
        assertEq(pcvOracle.isLiquidVenue(address(deposit1)), false);
        assertEq(pcvOracle.isIlliquidVenue(address(deposit1)), false);
        assertEq(pcvOracle.isVenue(address(deposit2)), false);
        assertEq(pcvOracle.isLiquidVenue(address(deposit2)), false);
        assertEq(pcvOracle.isIlliquidVenue(address(deposit2)), false);
        assertEq(pcvOracle.venueToOracle(address(deposit1)), address(0));
        assertEq(pcvOracle.venueToOracle(address(deposit2)), address(0));
    }

    function testAddNonEmptyVenuesRevertsIfOracleIsInvalid() public {
        uint256 currentTimestamp = 12345;
        vm.warp(currentTimestamp);

        // make deposit1 non-empty
        token1.mint(address(deposit1), 100e18);
        entry.deposit(address(deposit1));

        // set invalid oracle
        oracle1.setValues(1e18, false);

        // prepare add
        address[] memory venues = new address[](1);
        venues[0] = address(deposit1);
        address[] memory oracles = new address[](1);
        oracles[0] = address(oracle1);
        bool[] memory isLiquid = new bool[](1);
        isLiquid[0] = true;
        // add
        vm.prank(addresses.governorAddress);
        vm.expectRevert(bytes("PCVOracle: invalid oracle value"));
        pcvOracle.addVenues(venues, oracles, isLiquid);
    }

    function testRemoveNonEmptyVenuesRevertsIfOracleIsInvalid() public {
        uint256 currentTimestamp = 12345;
        vm.warp(currentTimestamp);

        // make deposit1 non-empty
        token1.mint(address(deposit1), 100e18);
        entry.deposit(address(deposit1));

        // set valid oracle
        oracle1.setValues(1e18, true);

        // prepare add
        address[] memory venues = new address[](1);
        venues[0] = address(deposit1);
        address[] memory oracles = new address[](1);
        oracles[0] = address(oracle1);
        bool[] memory isLiquid = new bool[](1);
        isLiquid[0] = true;
        // add
        vm.prank(addresses.governorAddress);
        pcvOracle.addVenues(venues, oracles, isLiquid);

        // set invalid oracle
        oracle1.setValues(1e18, false);

        // remove
        vm.prank(addresses.governorAddress);
        vm.expectRevert(bytes("PCVOracle: invalid oracle value"));
        pcvOracle.removeVenues(venues, isLiquid);
    }

    // ---------------- Access Control -----------------

    function testSetVenueOracleAcl() public {
        vm.expectRevert(bytes("CoreRef: Caller is not a governor"));
        pcvOracle.setVenueOracle(address(deposit1), address(oracle1));
    }

    function testAddVenuesAcl() public {
        address[] memory venues = new address[](1);
        address[] memory oracles = new address[](1);
        bool[] memory isLiquid = new bool[](1);

        vm.expectRevert(bytes("CoreRef: Caller is not a governor"));
        pcvOracle.addVenues(venues, oracles, isLiquid);
    }

    function testRemoveVenuesAcl() public {
        address[] memory venues = new address[](1);
        bool[] memory isLiquid = new bool[](1);

        vm.expectRevert(bytes("CoreRef: Caller is not a governor"));
        pcvOracle.removeVenues(venues, isLiquid);
    }

    // -------------------------------------------------
    // Accounting Checks
    // -------------------------------------------------

    function testTrackDepositValueOnAddAndRemove() public {
        // make deposit1 non-empty
        token1.mint(address(deposit1), 100e18);
        entry.deposit(address(deposit1));

        // set oracle values
        oracle1.setValues(1e18, true); // simulating "DAI" (1$ coin, 18 decimals)

        // add venue
        address[] memory venues = new address[](1);
        venues[0] = address(deposit1);
        address[] memory oracles = new address[](1);
        oracles[0] = address(oracle1);
        bool[] memory isLiquid = new bool[](1);
        isLiquid[0] = true;
        vm.prank(addresses.governorAddress);
        pcvOracle.addVenues(venues, oracles, isLiquid);

        // check getPcv()
        (
            uint256 liquidPcv1,
            uint256 illiquidPcv1,
            uint256 totalPcv1
        ) = pcvOracle.getTotalPcv();
        assertEq(liquidPcv1, 100e18); // 100$ liquid
        assertEq(illiquidPcv1, 0); // 0$ illiquid
        assertEq(totalPcv1, 100e18); // 100$ total

        // initial add already persisted in state
        assertEq(pcvOracle.lastIlliquidBalance(), 0);
        assertEq(pcvOracle.lastLiquidBalance(), 100e18);
        assertEq(pcvOracle.lastLiquidVenuePercentage(), 1e18); // 100%

        // remove venue
        vm.prank(addresses.governorAddress);
        pcvOracle.removeVenues(venues, isLiquid);

        // check getPcv()
        (
            uint256 liquidPcv2,
            uint256 illiquidPcv2,
            uint256 totalPcv2
        ) = pcvOracle.getTotalPcv();
        assertEq(liquidPcv2, 0); // 0$ liquid
        assertEq(illiquidPcv2, 0); // 0$ illiquid
        assertEq(totalPcv2, 0); // 0$ total

        // removed from state
        assertEq(pcvOracle.lastIlliquidBalance(), 0);
        assertEq(pcvOracle.lastLiquidBalance(), 0);
        assertEq(pcvOracle.lastLiquidVenuePercentage(), 1e18); // 100% by convention
    }

    function testAccountingOnHook() public {
        // make deposit1 non-empty
        token1.mint(address(deposit1), 100e18);
        entry.deposit(address(deposit1));

        // set oracle values
        oracle1.setValues(1e18, true); // simulating "DAI" (1$ coin, 18 decimals)
        oracle2.setValues(1e18 * 1e12, true); // simulating "USDC" (1$ coin, 6 decimals)

        // add venues
        address[] memory venues = new address[](2);
        venues[0] = address(deposit1);
        venues[1] = address(deposit2);
        address[] memory oracles = new address[](2);
        oracles[0] = address(oracle1);
        oracles[1] = address(oracle2);
        bool[] memory isLiquid = new bool[](2);
        isLiquid[0] = true;
        isLiquid[1] = false;
        vm.prank(addresses.governorAddress);
        pcvOracle.addVenues(venues, oracles, isLiquid);

        // check getPcv()
        (
            uint256 liquidPcv1,
            uint256 illiquidPcv1,
            uint256 totalPcv1
        ) = pcvOracle.getTotalPcv();
        assertEq(liquidPcv1, 100e18); // 100$ liquid
        assertEq(illiquidPcv1, 0); // 0$ illiquid
        assertEq(totalPcv1, 100e18); // 100$ total

        // the balances have not persisted in the state yet,
        // except for the initial 1$ liquid that was already here
        // when the liquid pcvdeposit was added to the oracle,
        // because there has been no hook calls from PCVdeposits
        // or addition/removal of venues in the PCV Oracle's state.
        assertEq(pcvOracle.lastIlliquidBalance(), 0);
        assertEq(pcvOracle.lastLiquidBalance(), 100e18);
        assertEq(pcvOracle.lastLiquidVenuePercentage(), 1e18); // 100%

        // grant roles to pcv deposits
        vm.startPrank(addresses.governorAddress);
        core.createRole(VoltRoles.LIQUID_PCV_DEPOSIT, VoltRoles.GOVERN);
        core.grantRole(VoltRoles.LIQUID_PCV_DEPOSIT, address(deposit1));
        core.createRole(VoltRoles.ILLIQUID_PCV_DEPOSIT, VoltRoles.GOVERN);
        core.grantRole(VoltRoles.ILLIQUID_PCV_DEPOSIT, address(deposit2));
        vm.stopPrank();

        // deposit 1 has 100$ + 300$
        token1.mint(address(deposit1), 300e18);
        entry.deposit(address(deposit1));
        // deposit 2 has 400$
        token2.mint(address(deposit2), 400e6);
        entry.deposit(address(deposit2));

        // check getPcv()
        (
            uint256 liquidPcv2,
            uint256 illiquidPcv2,
            uint256 totalPcv2
        ) = pcvOracle.getTotalPcv();
        assertEq(liquidPcv2, 100e18 + 300e18); // 400$ liquid
        assertEq(illiquidPcv2, 400e18); // 400$ illiquid
        assertEq(totalPcv2, 800e18); // 800$ total

        // the balances have not persisted in the state yet,
        // except for the initial 100$ liquid that was already here
        // when the liquid pcvdeposit was added to the oracle,
        // because there has been no hook calls from PCVdeposits
        // or addition/removal of venues in the PCV Oracle's state.
        assertEq(pcvOracle.lastIlliquidBalance(), 0);
        assertEq(pcvOracle.lastLiquidBalance(), 100e18);
        assertEq(pcvOracle.lastLiquidVenuePercentage(), 1e18); // 100%

        // A call from an illiquid PCVDeposit refreshes the state
        vm.startPrank(address(deposit2));
        core.lock(1);
        pcvOracle.updateIlliquidBalance(int256(400e6));
        core.unlock(0);
        vm.stopPrank();
        assertEq(pcvOracle.lastIlliquidBalance(), 400e18); // 400$ illiquid
        assertEq(pcvOracle.lastLiquidBalance(), 100e18); // 100$ liquid
        assertEq(pcvOracle.lastLiquidVenuePercentage(), 0.2e18); // 20% liquid

        // A call from a liquid PCVDeposit refreshes the state
        vm.startPrank(address(deposit1));
        core.lock(1);
        pcvOracle.updateLiquidBalance(int256(300e18));
        core.unlock(0);
        vm.stopPrank();
        assertEq(pcvOracle.lastIlliquidBalance(), 400e18); // 400$ illiquid
        assertEq(pcvOracle.lastLiquidBalance(), 400e18); // 400$ liquid
        assertEq(pcvOracle.lastLiquidVenuePercentage(), 0.5e18); // 50% liquid
    }

    function testGetPcvRevertIfOracleInvalid() public {
        // make deposit1 non-empty
        token1.mint(address(deposit1), 100e18);
        entry.deposit(address(deposit1));

        // set oracle values
        oracle1.setValues(123456, true); // oracle valid

        // add venues
        address[] memory venues = new address[](1);
        venues[0] = address(deposit1);
        address[] memory oracles = new address[](1);
        oracles[0] = address(oracle1);
        bool[] memory isLiquid = new bool[](1);
        isLiquid[0] = true;
        vm.prank(addresses.governorAddress);
        pcvOracle.addVenues(venues, oracles, isLiquid);

        // set oracle values
        oracle1.setValues(123456, false); // oracle unvalid

        // getPcv() reverts because oracle is invalid
        vm.expectRevert(bytes("PCVOracle: invalid oracle value"));
        pcvOracle.getTotalPcv();
    }

    // -------------------------------------------------
    // PCV Deposit hooks, accounting checks
    // -------------------------------------------------

    // updateLiquidBalance()
    // updateIlliquidBalance()

    // TODO: the 2 happy paths, check events etc
    // TODO: updateActualRate() is called, check the change on liquidReserves
    // TODO: calling PCVDeposit has the role, but isn't listed in the venues
    // TODO: Oracle Invalid

    // ---------------- Access Control -----------------

    function testUpdateLiquidBalanceAcl() public {
        vm.expectRevert(bytes("UNAUTHORIZED"));
        pcvOracle.updateLiquidBalance(0.5e18);
    }

    function testUpdateIlliquidBalanceAcl() public {
        vm.expectRevert(bytes("UNAUTHORIZED"));
        pcvOracle.updateIlliquidBalance(0.5e18);
    }
}
