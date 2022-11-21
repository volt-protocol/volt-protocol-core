// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";

import {Vm} from "./../utils/Vm.sol";
import {ICore} from "../../../core/ICore.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {ICoreV2} from "../../../core/ICoreV2.sol";
import {Decimal} from "./../../../external/Decimal.sol";
import {Constants} from "./../../../Constants.sol";
import {PCVOracle} from "../../../oracle/PCVOracle.sol";
import {MockPCVDepositV3} from "../../../mock/MockPCVDepositV3.sol";
import {MockERC20} from "../../../mock/MockERC20.sol";
import {MockOracle} from "../../../mock/MockOracle.sol";
import {VoltRoles} from "../../../core/VoltRoles.sol";
import {getCoreV2, getAddresses, VoltTestAddresses} from "./../utils/Fixtures.sol";

contract PCVOracleUnitTest is DSTest {
    using Decimal for Decimal.D256;
    using SafeCast for *;

    ICoreV2 private core;
    Vm public constant vm = Vm(HEVM_ADDRESS);
    VoltTestAddresses public addresses = getAddresses();

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
        core = getCoreV2();
        pcvOracle = new PCVOracle(address(core));

        // mock utils
        oracle1 = new MockOracle();
        oracle2 = new MockOracle();
        token1 = new MockERC20();
        token2 = new MockERC20();
        deposit1 = new MockPCVDepositV3(address(core), address(token1));
        deposit2 = new MockPCVDepositV3(address(core), address(token2));

        // grant role
        vm.prank(addresses.governorAddress);
        core.grantLocker(address(pcvOracle));
    }

    function testSetup() public {
        assertEq(pcvOracle.voltOracle(), address(0));
        assertEq(pcvOracle.lastIlliquidBalance(), 0);
        assertEq(pcvOracle.lastLiquidBalance(), 0);
        assertEq(pcvOracle.getLiquidVenues().length, 0);
        assertEq(pcvOracle.getIlliquidVenues().length, 0);
        assertEq(pcvOracle.getAllVenues().length, 0);
        assertEq(pcvOracle.getLiquidVenuePercentage(), 1e18);
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

    function testAccountingOnHook() public {
        // make deposit1 non-empty
        token1.mint(address(deposit1), 1e18);
        deposit1.deposit();

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

        // grant roles to pcv deposits
        vm.startPrank(addresses.governorAddress);
        core.createRole(VoltRoles.LIQUID_PCV_DEPOSIT_ROLE, VoltRoles.GOVERNOR);
        core.grantRole(VoltRoles.LIQUID_PCV_DEPOSIT_ROLE, address(deposit1));
        core.createRole(
            VoltRoles.ILLIQUID_PCV_DEPOSIT_ROLE,
            VoltRoles.GOVERNOR
        );
        core.grantRole(VoltRoles.ILLIQUID_PCV_DEPOSIT_ROLE, address(deposit2));
        core.createRole(VoltRoles.LOCKER_ROLE, VoltRoles.GOVERNOR);
        core.grantRole(VoltRoles.LOCKER_ROLE, address(deposit1));
        core.grantRole(VoltRoles.LOCKER_ROLE, address(deposit2));
        vm.stopPrank();

        // set oracle values
        oracle1.setValues(1e18, true); // simulating "DAI" (1$ coin, 18 decimals)
        oracle2.setValues(1e18 * 1e12, true); // simulating "USDC" (1$ coin, 6 decimals)

        // deposit 1 has 123$
        token1.mint(address(deposit1), 123e18);
        deposit1.deposit();
        // deposit 2 has 456$
        token2.mint(address(deposit2), 456e6);
        deposit2.deposit();

        // check getPcv()
        (uint256 liquidPcv, uint256 illiquidPcv, uint256 totalPcv) = pcvOracle
            .getTotalPcv();
        assertEq(liquidPcv, 123e18); // 123$ liquid
        assertEq(illiquidPcv, 456e18); // 456$ illiquid
        assertEq(totalPcv, 579e18); // 579$ total

        // the balances have not persisted in the state yet
        // because there has been no hook calls from PCVdeposits
        // or addition/removal of venues in the PCV Oracle's state.
        assertEq(pcvOracle.lastIlliquidBalance(), 0);
        assertEq(pcvOracle.lastLiquidBalance(), 0);
        assertEq(pcvOracle.getLiquidVenuePercentage(), 1e18);

        // A call from an illiquid PCVDeposit refreshes the state
        vm.prank(address(deposit2));
        pcvOracle.updateIlliquidBalance(int256(456e6));
        assertEq(pcvOracle.lastIlliquidBalance(), 456e18);
        assertEq(pcvOracle.lastLiquidBalance(), 0);
        assertEq(pcvOracle.getLiquidVenuePercentage(), 0);
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
