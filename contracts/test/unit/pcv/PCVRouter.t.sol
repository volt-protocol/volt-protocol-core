// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Vm} from "../utils/Vm.sol";
import {Test} from "../../../../forge-std/src/Test.sol";
import {CoreV2} from "../../../core/CoreV2.sol";
import {PCVRouter} from "../../../pcv/PCVRouter.sol";
import {PCVOracle} from "../../../oracle/PCVOracle.sol";
import {MockERC20} from "../../../mock/MockERC20.sol";
import {VoltRoles} from "../../../core/VoltRoles.sol";
import {getCoreV2} from "./../utils/Fixtures.sol";
import {IPCVOracle} from "../../../oracle/IPCVOracle.sol";
import {MockOracle} from "../../../mock/MockOracle.sol";
import {SystemEntry} from "../../../entry/SystemEntry.sol";
import {MockPCVSwapper} from "../../../mock/MockPCVSwapper.sol";
import {MockPCVDepositV3} from "../../../mock/MockPCVDepositV3.sol";
import {TestAddresses as addresses} from "../utils/TestAddresses.sol";
import {IGlobalReentrancyLock, GlobalReentrancyLock} from "../../../core/GlobalReentrancyLock.sol";

contract PCVRouterUnitTest is Test {
    CoreV2 private core;
    SystemEntry public entry;

    // reference to the volt pcv oracle
    PCVOracle private pcvOracle;

    // reference to the volt pcv router
    PCVRouter private pcvRouter;

    // global reentrancy lock
    IGlobalReentrancyLock private lock;

    // test Tokens
    MockERC20 private token1;
    MockERC20 private token2;
    // test PCV Deposits
    MockPCVDepositV3 private depositToken1A;
    MockPCVDepositV3 private depositToken1B;
    MockPCVDepositV3 private depositToken2A;
    MockPCVDepositV3 private depositToken2B;
    // test Oracles
    MockOracle private oracle;
    // test swapper
    MockPCVSwapper swapper;

    // PCVRouter events
    event PCVMovement(
        address indexed source,
        address indexed destination,
        uint256 amountSource,
        uint256 amountDestination
    );
    event Swap(
        address indexed assetIn,
        address indexed assetOut,
        address indexed destination,
        uint256 amountIn,
        uint256 amountOut
    );
    event PCVSwapperAdded(address indexed swapper);
    event PCVSwapperRemoved(address indexed swapper);

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
        lock = IGlobalReentrancyLock(
            address(new GlobalReentrancyLock(address(core)))
        );

        // mock utils
        oracle = new MockOracle();
        token1 = new MockERC20();
        token2 = new MockERC20();
        depositToken1A = new MockPCVDepositV3(address(core), address(token1));
        depositToken1B = new MockPCVDepositV3(address(core), address(token1));
        depositToken2A = new MockPCVDepositV3(address(core), address(token2));
        depositToken2B = new MockPCVDepositV3(address(core), address(token2));
        swapper = new MockPCVSwapper(token1, token2);

        // init oracle
        oracle.setValues(1e18, true);

        // grant roles
        vm.startPrank(addresses.governorAddress);
        core.grantLocker(address(entry));
        core.grantLocker(address(pcvOracle));
        core.grantLocker(address(depositToken1A));
        core.grantLocker(address(depositToken1B));
        core.grantLocker(address(depositToken2A));
        core.grantLocker(address(depositToken2B));
        core.grantLocker(address(pcvRouter));
        core.grantPCVController(address(pcvRouter));
        core.createRole(VoltRoles.PCV_MOVER, VoltRoles.GOVERNOR);
        core.grantRole(VoltRoles.PCV_MOVER, address(this));
        core.setGlobalReentrancyLock(lock);
        vm.stopPrank();

        // setup deposits
        token1.mint(address(depositToken1A), 100e18);
        token1.mint(address(depositToken1B), 100e18);
        token2.mint(address(depositToken2A), 100e18);
        token2.mint(address(depositToken2B), 100e18);
        entry.deposit(address(depositToken1A));
        entry.deposit(address(depositToken1B));
        entry.deposit(address(depositToken2A));
        entry.deposit(address(depositToken2B));

        // setup PCVOracle
        address[] memory venues = new address[](4);
        venues[0] = address(depositToken1A);
        venues[1] = address(depositToken1B);
        venues[2] = address(depositToken2A);
        venues[3] = address(depositToken2B);
        address[] memory oracles = new address[](4);
        oracles[0] = address(oracle);
        oracles[1] = address(oracle);
        oracles[2] = address(oracle);
        oracles[3] = address(oracle);
        vm.prank(addresses.governorAddress);
        pcvOracle.addVenues(venues, oracles);

        // setup PCVRouter
        vm.prank(addresses.governorAddress);
        core.setPCVOracle(IPCVOracle(address(pcvOracle)));
    }

    function testSetup() public {
        assertEq(address(pcvRouter.core()), address(core));
        assertEq(address(core.pcvOracle()), address(pcvOracle));
        assertEq(pcvRouter.getPCVSwappers().length, 0);
    }

    // -------------------------------------------------
    // PCVSwapper Management API
    // -------------------------------------------------

    function testAddPCVSwappers() public {
        assertEq(pcvRouter.getPCVSwappers().length, 0);

        vm.prank(addresses.governorAddress);
        address[] memory whitelistedSwapperAddresses = new address[](1);
        whitelistedSwapperAddresses[0] = address(swapper);
        vm.expectEmit(true, false, false, true, address(pcvRouter));
        emit PCVSwapperAdded(address(swapper));
        pcvRouter.addPCVSwappers(whitelistedSwapperAddresses);

        assertEq(pcvRouter.getPCVSwappers().length, 1);
        assertEq(pcvRouter.getPCVSwappers()[0], address(swapper));
        assertEq(pcvRouter.isPCVSwapper(address(swapper)), true);
    }

    function testAddPCVSwappersRevertIfAlreadyExisting() public {
        vm.prank(addresses.governorAddress);
        address[] memory whitelistedSwapperAddresses = new address[](2);
        whitelistedSwapperAddresses[0] = address(swapper);
        whitelistedSwapperAddresses[1] = address(swapper);
        vm.expectRevert("PCVRouter: Failed to add swapper");
        pcvRouter.addPCVSwappers(whitelistedSwapperAddresses);
    }

    function testAddPCVSwappersAcl() public {
        address[] memory whitelistedSwapperAddresses = new address[](1);
        whitelistedSwapperAddresses[0] = address(swapper);

        vm.expectRevert("CoreRef: Caller is not a governor");
        pcvRouter.addPCVSwappers(whitelistedSwapperAddresses);
    }

    function testRemovePCVSwappers() public {
        vm.prank(addresses.governorAddress);
        address[] memory whitelistedSwapperAddresses = new address[](1);
        whitelistedSwapperAddresses[0] = address(swapper);
        pcvRouter.addPCVSwappers(whitelistedSwapperAddresses);

        assertEq(pcvRouter.getPCVSwappers().length, 1);
        assertEq(pcvRouter.getPCVSwappers()[0], address(swapper));
        assertEq(pcvRouter.isPCVSwapper(address(swapper)), true);

        vm.prank(addresses.governorAddress);
        vm.expectEmit(true, false, false, true, address(pcvRouter));
        emit PCVSwapperRemoved(address(swapper));
        pcvRouter.removePCVSwappers(whitelistedSwapperAddresses);

        assertEq(pcvRouter.getPCVSwappers().length, 0);
    }

    function testRemovePCVSwappersRevertIfNotExisting() public {
        vm.prank(addresses.governorAddress);
        address[] memory whitelistedSwapperAddresses = new address[](1);
        whitelistedSwapperAddresses[0] = address(swapper);
        vm.expectRevert("PCVRouter: Failed to remove swapper");
        pcvRouter.removePCVSwappers(whitelistedSwapperAddresses);
    }

    function testRemovePCVSwappersAcl() public {
        address[] memory whitelistedSwapperAddresses = new address[](1);
        whitelistedSwapperAddresses[0] = address(swapper);

        vm.expectRevert("CoreRef: Caller is not a governor");
        pcvRouter.removePCVSwappers(whitelistedSwapperAddresses);
    }

    // -------------------------------------------------
    // Happy Path
    // -------------------------------------------------

    function testMovePCVEvents() public {
        // PCVMovement
        vm.expectEmit(true, true, false, true, address(pcvRouter));
        emit PCVMovement(
            address(depositToken1A),
            address(depositToken1B),
            50e18,
            50e18
        );

        pcvRouter.movePCV(
            address(depositToken1A), // source
            address(depositToken1B), // destination
            address(0), // swapper
            50e18, // amount
            address(token1), // sourceAsset
            address(token1) // destinationAsset
        );
    }

    function testMovePCVBalances() public {
        assertEq(depositToken1A.balance(), 100e18);
        assertEq(depositToken1B.balance(), 100e18);

        vm.expectCall(
            address(depositToken1A),
            abi.encodeWithSignature(
                "withdraw(address,uint256)",
                address(depositToken1B),
                50e18
            )
        );
        vm.expectCall(
            address(depositToken1B),
            abi.encodeWithSignature("deposit()")
        );
        pcvRouter.movePCV(
            address(depositToken1A), // source
            address(depositToken1B), // destination
            address(0), // swapper
            50e18, // amount
            address(token1), // sourceAsset
            address(token1) // destinationAsset
        );

        assertEq(depositToken1A.balance(), 50e18);
        assertEq(depositToken1B.balance(), 150e18);
    }

    function testMovePCVUsingSwapper() public {
        assertEq(depositToken1A.balance(), 100e18);
        assertEq(depositToken2A.balance(), 100e18);

        vm.prank(addresses.governorAddress);
        address[] memory whitelistedSwapperAddresses = new address[](1);
        whitelistedSwapperAddresses[0] = address(swapper);
        pcvRouter.addPCVSwappers(whitelistedSwapperAddresses);

        vm.expectEmit(true, true, true, true, address(swapper));
        emit Swap(
            address(token1), // assetIn
            address(token2), // assetOut
            address(depositToken2A), // destination
            50e18, // amountIn
            50e18 // amountOut
        );
        pcvRouter.movePCV(
            address(depositToken1A), // source
            address(depositToken2A), // destination
            address(swapper), // swapper
            50e18, // amount
            address(token1), // sourceAsset
            address(token2) // destinationAsset
        );

        assertEq(depositToken1A.balance(), 50e18);
        assertEq(depositToken2A.balance(), 150e18);
    }

    function testMovePCVUncheckedBalances() public {
        assertEq(depositToken1A.balance(), 100e18);
        assertEq(depositToken1B.balance(), 100e18);

        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(this));

        vm.expectCall(
            address(depositToken1A),
            abi.encodeWithSignature(
                "withdraw(address,uint256)",
                address(depositToken1B),
                50e18
            )
        );
        vm.expectCall(
            address(depositToken1B),
            abi.encodeWithSignature("deposit()")
        );
        pcvRouter.movePCVUnchecked(
            address(depositToken1A), // source
            address(depositToken1B), // destination
            address(0), // swapper
            50e18, // amount
            address(token1), // sourceAsset
            address(token1) // destinationAsset
        );

        assertEq(depositToken1A.balance(), 50e18);
        assertEq(depositToken1B.balance(), 150e18);
    }

    function testMoveAllPCVUncheckedBalances() public {
        assertEq(depositToken1A.balance(), 100e18);
        assertEq(depositToken1B.balance(), 100e18);

        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(this));

        vm.expectCall(
            address(depositToken1A),
            abi.encodeWithSignature(
                "withdraw(address,uint256)",
                address(depositToken1B),
                100e18
            )
        );
        vm.expectCall(
            address(depositToken1B),
            abi.encodeWithSignature("deposit()")
        );
        pcvRouter.moveAllPCVUnchecked(
            address(depositToken1A), // source
            address(depositToken1B), // destination
            address(0), // swapper
            address(token1), // sourceAsset
            address(token1) // destinationAsset
        );

        assertEq(depositToken1A.balance(), 0);
        assertEq(depositToken1B.balance(), 200e18);
    }

    // -------------------------------------------------
    // Input Validation
    // -------------------------------------------------

    function testMovePCVInvalidSource() public {
        vm.expectRevert("PCVRouter: invalid source");
        pcvRouter.movePCV(
            address(this), // source, not a PCVDeposit
            address(depositToken2A), // destination
            address(0), // swapper
            50e18, // amount
            address(this), // sourceAsset
            address(token2) // destinationAsset
        );
    }

    function testMovePCVInvalidDestination() public {
        vm.expectRevert("PCVRouter: invalid destination");
        pcvRouter.movePCV(
            address(depositToken1A), // source
            address(this), // destination, not a PCVDeposit
            address(0), // swapper
            50e18, // amount
            address(token1), // sourceAsset
            address(token2) // destinationAsset
        );
    }

    function testMovePCVWrongToken() public {
        vm.expectRevert("PCVRouter: invalid source asset");
        pcvRouter.movePCV(
            address(depositToken1A), // source
            address(depositToken2A), // destination
            address(0), // swapper
            50e18, // amount
            address(token2), // sourceAsset, wrong value
            address(token2) // destinationAsset
        );

        vm.expectRevert("PCVRouter: invalid destination asset");
        pcvRouter.movePCV(
            address(depositToken1A), // source
            address(depositToken2A), // destination
            address(0), // swapper
            50e18, // amount
            address(token1), // sourceAsset
            address(token1) // destinationAsset, wrong value
        );
    }

    function testMovePCVInvalidSwapper() public {
        vm.expectRevert("PCVRouter: invalid swapper");
        pcvRouter.movePCV(
            address(depositToken1A), // source
            address(depositToken2A), // destination
            address(this), // swapper
            50e18, // amount
            address(token1), // sourceAsset
            address(token2) // destinationAsset
        );
    }

    function testMovePCVUnsupportedSwap() public {
        vm.prank(addresses.governorAddress);
        address[] memory whitelistedSwapperAddresses = new address[](1);
        whitelistedSwapperAddresses[0] = address(swapper);
        pcvRouter.addPCVSwappers(whitelistedSwapperAddresses);

        vm.expectRevert("PCVRouter: unsupported swap");
        pcvRouter.movePCV(
            address(depositToken2A), // source
            address(depositToken1A), // destination
            address(swapper), // swapper
            50e18, // amount
            address(token2), // sourceAsset
            address(token1) // destinationAsset
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
            address(depositToken1A), // source
            address(depositToken1B), // destination
            address(0), // swapper
            50e18, // amount
            address(token1), // sourceAsset
            address(token1) // destinationAsset
        );
    }

    function testMovePCVAcl() public {
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(address(0)); // doesn't have PCV_MOVER role
        pcvRouter.movePCV(
            address(depositToken1A), // source
            address(depositToken1B), // destination
            address(0), // swapper
            50e18, // amount
            address(token1), // sourceAsset
            address(token1) // destinationAsset
        );
    }

    function testMovePCVUncheckedRevertIfPaused() public {
        vm.prank(addresses.governorAddress);
        pcvRouter.pause();

        vm.expectRevert("Pausable: paused");
        pcvRouter.movePCVUnchecked(
            address(depositToken1A), // source
            address(depositToken1B), // destination
            address(0), // swapper
            50e18, // amount
            address(token1), // sourceAsset
            address(token1) // destinationAsset
        );
    }

    function testMovePCVUncheckedAcl() public {
        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        vm.prank(address(0)); // doesn't have PCV_CONTROLLER role
        pcvRouter.movePCVUnchecked(
            address(depositToken1A), // source
            address(depositToken1B), // destination
            address(0), // swapper
            50e18, // amount
            address(token1), // sourceAsset
            address(token1) // destinationAsset
        );
    }

    function testMoveAllPCVUncheckedRevertIfPaused() public {
        vm.prank(addresses.governorAddress);
        pcvRouter.pause();

        vm.expectRevert("Pausable: paused");
        pcvRouter.moveAllPCVUnchecked(
            address(depositToken1A), // source
            address(depositToken1B), // destination
            address(0), // swapper
            address(token1), // sourceAsset
            address(token1) // destinationAsset
        );
    }

    function testMoveAllPCVUncheckedAcl() public {
        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        vm.prank(address(0)); // doesn't have PCV_CONTROLLER role
        pcvRouter.moveAllPCVUnchecked(
            address(depositToken1A), // source
            address(depositToken1B), // destination
            address(0), // swapper
            address(token1), // sourceAsset
            address(token1) // destinationAsset
        );
    }

    // -------------------------------------------------
    // Configuration Errors
    // -------------------------------------------------

    function testMovePCVRevertIfNotPCVController() public {
        vm.prank(addresses.governorAddress);
        core.revokePCVController(address(pcvRouter));

        depositToken1A.setCheckPCVController(true);

        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        pcvRouter.movePCV(
            address(depositToken1A), // source
            address(depositToken1B), // destination
            address(0), // swapper
            50e18, // amount
            address(token1), // sourceAsset
            address(token1) // destinationAsset
        );
    }

    function testMovePCVRevertIfNotLocker() public {
        vm.prank(addresses.governorAddress);
        core.revokeLocker(address(pcvRouter));

        vm.expectRevert("UNAUTHORIZED");
        pcvRouter.movePCV(
            address(depositToken1A), // source
            address(depositToken1B), // destination
            address(0), // swapper
            50e18, // amount
            address(token1), // sourceAsset
            address(token1) // destinationAsset
        );
    }
}
