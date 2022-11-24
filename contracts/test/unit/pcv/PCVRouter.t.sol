// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Vm} from "../utils/Vm.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {CoreV2} from "../../../core/CoreV2.sol";
import {PCVRouter} from "../../../pcv/PCVRouter.sol";
import {PCVOracle} from "../../../oracle/PCVOracle.sol";
import {SystemEntry} from "../../../entry/SystemEntry.sol";
import {MockPCVDepositV3} from "../../../mock/MockPCVDepositV3.sol";
import {MockERC20} from "../../../mock/MockERC20.sol";
import {MockOracle} from "../../../mock/MockOracle.sol";
import {VoltRoles} from "../../../core/VoltRoles.sol";
import {getCoreV2, getAddresses, VoltTestAddresses} from "./../utils/Fixtures.sol";

contract PCVRouterUnitTest is DSTest {
    CoreV2 private core;
    SystemEntry public entry;
    Vm public constant vm = Vm(HEVM_ADDRESS);
    VoltTestAddresses public addresses = getAddresses();

    // reference to the volt pcv oracle
    PCVOracle private pcvOracle;

    // reference to the volt pcv router
    PCVRouter private pcvRouter;

    // test Tokens
    MockERC20 private token1;
    MockERC20 private token2;
    // test PCV Deposits
    MockPCVDepositV3 private depositToken1Liquid;
    MockPCVDepositV3 private depositToken1Illiquid;
    MockPCVDepositV3 private depositToken2Liquid;
    MockPCVDepositV3 private depositToken2Illiquid;
    // test Oracles
    MockOracle private oracle;

    // PCVRouter events
    event PCVMovement(
        address indexed source,
        address indexed destination,
        uint256 amount
    );

    // mocked DynamicVoltSystemOracle behavior to prevent reverts
    // of the PCVOracle
    uint256 private liquidReserves;

    function updateActualRate(uint256 _liquidReserves) external {
        liquidReserves = _liquidReserves;
    }

    function setUp() public {
        // volt system
        core = CoreV2(address(getCoreV2()));
        pcvOracle = new PCVOracle(address(core));
        pcvRouter = new PCVRouter(address(core));
        entry = new SystemEntry(address(core));

        // mock utils
        oracle = new MockOracle();
        token1 = new MockERC20();
        token2 = new MockERC20();
        depositToken1Liquid = new MockPCVDepositV3(
            address(core),
            address(token1)
        );
        depositToken1Illiquid = new MockPCVDepositV3(
            address(core),
            address(token1)
        );
        depositToken2Liquid = new MockPCVDepositV3(
            address(core),
            address(token2)
        );
        depositToken2Illiquid = new MockPCVDepositV3(
            address(core),
            address(token2)
        );

        // init oracle
        oracle.setValues(1e18, true);

        // grant roles
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(address(entry));
        core.grantLocker(address(pcvOracle));
        core.grantLocker(address(depositToken1Liquid));
        core.grantLocker(address(depositToken1Illiquid));
        core.grantLocker(address(depositToken2Liquid));
        core.grantLocker(address(depositToken2Illiquid));
        core.grantLocker(address(pcvRouter));
        core.grantPCVController(address(pcvRouter));
        core.createRole(VoltRoles.PCV_MOVER, VoltRoles.GOVERNOR);
        core.grantRole(VoltRoles.PCV_MOVER, address(this));
        vm.stopPrank();

        // setup deposits
        token1.mint(address(depositToken1Liquid), 100e18);
        token1.mint(address(depositToken1Illiquid), 100e18);
        token2.mint(address(depositToken2Liquid), 100e18);
        token2.mint(address(depositToken2Illiquid), 100e18);
        entry.deposit(address(depositToken1Liquid));
        entry.deposit(address(depositToken1Illiquid));
        entry.deposit(address(depositToken2Liquid));
        entry.deposit(address(depositToken2Illiquid));

        // setup PCVOracle
        address[] memory venues = new address[](4);
        venues[0] = address(depositToken1Liquid);
        venues[1] = address(depositToken1Illiquid);
        venues[2] = address(depositToken2Liquid);
        venues[3] = address(depositToken2Illiquid);
        address[] memory oracles = new address[](4);
        oracles[0] = address(oracle);
        oracles[1] = address(oracle);
        oracles[2] = address(oracle);
        oracles[3] = address(oracle);
        bool[] memory isLiquid = new bool[](4);
        isLiquid[0] = true;
        isLiquid[1] = false;
        isLiquid[2] = true;
        isLiquid[3] = false;
        vm.prank(addresses.governorAddress);
        pcvOracle.addVenues(venues, oracles, isLiquid);

        // setup PCVRouter
        vm.prank(addresses.governorAddress);
        pcvRouter.setPCVOracle(address(pcvOracle));
    }

    function testSetup() public {
        assertEq(address(pcvRouter.core()), address(core));
        assertEq(pcvRouter.pcvOracle(), address(pcvOracle));
    }

    // -------------------------------------------------
    // Happy Path
    // -------------------------------------------------

    function testMovePCVEvents() public {
        // PCVMovement
        vm.expectEmit(true, true, false, true, address(pcvRouter));
        emit PCVMovement(
            address(depositToken1Liquid),
            address(depositToken1Illiquid),
            50e18
        );

        pcvRouter.movePCV(
            address(depositToken1Liquid),
            address(depositToken1Illiquid),
            true,
            false,
            50e18
        );
    }

    function testMovePCVBalances() public {
        assertEq(depositToken1Liquid.balance(), 100e18);
        assertEq(depositToken1Illiquid.balance(), 100e18);

        pcvRouter.movePCV(
            address(depositToken1Liquid),
            address(depositToken1Illiquid),
            true,
            false,
            50e18
        );

        assertEq(depositToken1Liquid.balance(), 50e18);
        assertEq(depositToken1Illiquid.balance(), 150e18);
    }

    // -------------------------------------------------
    // Input Validation
    // -------------------------------------------------

    function testMovePCVInvalidSource() public {
        vm.expectRevert("PCVRouter: invalid source");
        pcvRouter.movePCV(
            address(this), // not a PCVDeposit
            address(depositToken2Liquid),
            true,
            true,
            50e18
        );

        vm.expectRevert("PCVRouter: invalid source");
        pcvRouter.movePCV(
            address(depositToken1Illiquid),
            address(depositToken2Liquid),
            true, // expected liquid but is illiquid
            true,
            50e18
        );
    }

    function testMovePCVInvalidDestination() public {
        vm.expectRevert("PCVRouter: invalid destination");
        pcvRouter.movePCV(
            address(depositToken1Liquid),
            address(this), // not a PCVDeposit
            true,
            true,
            50e18
        );

        vm.expectRevert("PCVRouter: invalid destination");
        pcvRouter.movePCV(
            address(depositToken1Liquid),
            address(depositToken2Illiquid),
            true,
            true, // expected liquid but is illiquid
            50e18
        );
    }

    function testMovePCVWrongToken() public {
        vm.expectRevert("PCVRouter: invalid route");
        pcvRouter.movePCV(
            address(depositToken1Liquid),
            address(depositToken2Liquid),
            true,
            true,
            50e18
        );
    }

    // -------------------------------------------------
    // Access Control
    // -------------------------------------------------

    function testMovePCVRevertIfPaused() public {
        vm.prank(addresses.governorAddress);
        pcvRouter.pause();

        vm.expectRevert("Pausable: paused");
        pcvRouter.movePCV(
            address(depositToken1Liquid),
            address(depositToken1Illiquid),
            true,
            false,
            50e18
        );
    }

    function testMovePCVAcl() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(address(0)); // doesn't have PCV_MOVER role
        pcvRouter.movePCV(
            address(depositToken1Liquid),
            address(depositToken1Illiquid),
            true,
            false,
            50e18
        );
    }

    // -------------------------------------------------
    // Configuration Errors
    // -------------------------------------------------

    function testMovePCVRevertIfNotPCVController() public {
        vm.prank(addresses.governorAddress);
        core.revokePCVController(address(pcvRouter));

        depositToken1Liquid.setCheckPCVController(true);

        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        pcvRouter.movePCV(
            address(depositToken1Liquid),
            address(depositToken1Illiquid),
            true,
            false,
            50e18
        );
    }

    function testMovePCVRevertIfNotLocker() public {
        vm.prank(addresses.governorAddress);
        core.revokeLocker(address(pcvRouter));

        vm.expectRevert("GlobalReentrancyLock: missing locker role");
        pcvRouter.movePCV(
            address(depositToken1Liquid),
            address(depositToken1Illiquid),
            true,
            false,
            50e18
        );
    }
}
