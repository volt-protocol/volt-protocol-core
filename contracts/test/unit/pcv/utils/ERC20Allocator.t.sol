pragma solidity =0.8.13;

import {Vm} from "./../../utils/Vm.sol";
import {ICore} from "../../../../core/ICore.sol";
import {DSTest} from "./../../utils/DSTest.sol";
import {MockERC20} from "../../../../mock/MockERC20.sol";
import {TribeRoles} from "../../../../core/TribeRoles.sol";
import {ERC20Allocator} from "../../../../pcv/utils/ERC20Allocator.sol";
import {PCVGuardAdmin} from "../../../../pcv/PCVGuardAdmin.sol";
import {PCVDeposit} from "../../../../pcv/PCVDeposit.sol";
import {ERC20HoldingPCVDeposit} from "../../../../pcv/ERC20HoldingPCVDeposit.sol";
import {getCore, getAddresses, VoltTestAddresses} from "./../../utils/Fixtures.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "hardhat/console.sol";

contract UnitTestERC20Allocator is DSTest {
    /// @notice emitted when an existing deposit is updated
    event PSMTargetBalanceUpdated(address psm, uint248 targetBalance);

    /// @notice PSM deletion event
    event PSMDeleted(address psm);

    /// @notice event emitted when tokens are dripped
    event Dripped(uint256 amount);

    /// @notice event emitted in do action when neither skim nor drip could be triggered
    event NoOp();

    /// @notice emitted when an existing deposit is deleted
    event DepositDeleted(address psm);

    ICore private core;
    Vm public constant vm = Vm(HEVM_ADDRESS);
    VoltTestAddresses public addresses = getAddresses();

    /// @notice reference to the PCVDeposit to pull from
    ERC20HoldingPCVDeposit private pcvDeposit;

    /// @notice reference to the PCVDeposit to push to
    ERC20HoldingPCVDeposit private psm;

    /// @notice reference to the ERC20
    ERC20Allocator private allocator;

    /// @notice token to push
    MockERC20 private token;

    /// @notice threshold over which to pull tokens from pull deposit
    uint248 private constant targetBalance = 100_000e18;

    /// @notice maximum rate limit per second in RateLimitedV2
    uint256 private constant maxRateLimitPerSecond = 1_000_000e18;

    /// @notice rate limit per second in RateLimitedV2
    uint128 private constant rateLimitPerSecond = 10_000e18;

    /// @notice buffer cap in RateLimitedV2
    uint128 private constant bufferCap = 10_000_000e18;

    function setUp() public {
        core = getCore();
        token = new MockERC20();

        pcvDeposit = new ERC20HoldingPCVDeposit(
            address(core),
            IERC20(address(token)),
            address(0)
        );

        psm = new ERC20HoldingPCVDeposit(
            address(core),
            IERC20(address(token)),
            address(0)
        );

        allocator = new ERC20Allocator(
            address(core),
            maxRateLimitPerSecond,
            rateLimitPerSecond,
            bufferCap
        );

        vm.startPrank(addresses.governorAddress);
        allocator.connectPSM(address(psm), targetBalance, 0);
        allocator.connectDeposit(address(psm), address(pcvDeposit));
        vm.stopPrank();
    }

    function testSetup() public {
        assertEq(address(allocator.core()), address(core));
        (
            address psmToken,
            uint248 psmTargetBalance,
            int8 decimalsNormalizer
        ) = allocator.allPSMs(address(psm));

        address psmAddress = allocator.pcvDepositToPSM(address(pcvDeposit));

        assertEq(psmTargetBalance, targetBalance);
        assertEq(decimalsNormalizer, 0);
        assertEq(psmToken, address(token));
        assertEq(allocator.buffer(), bufferCap);
        assertEq(targetBalance, allocator.targetBalance(address(psm)));
        assertEq(psmAddress, address(psm));

        assertTrue(!allocator.checkDripCondition(address(pcvDeposit))); /// drip action not allowed, due to 0 balance
        assertTrue(!allocator.checkSkimCondition(address(pcvDeposit))); /// skim action not allowed, not over threshold
        assertTrue(!allocator.checkActionAllowed(address(pcvDeposit))); /// neither drip nor skim action allowed
    }

    function testSkimFailsWhenUnderFunded() public {
        assertTrue(!allocator.checkSkimCondition(address(pcvDeposit)));
        assertTrue(!allocator.checkDripCondition(address(pcvDeposit))); /// drip action not allowed, due to 0 balance
        assertTrue(!allocator.checkActionAllowed(address(pcvDeposit)));

        vm.expectRevert("ERC20Allocator: skim condition not met");
        allocator.skim(address(pcvDeposit));
    }

    function testDripFailsWhenUnderFunded() public {
        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(allocator));
        token.mint(address(psm), targetBalance * 2);

        assertTrue(!allocator.checkDripCondition(address(pcvDeposit)));
        assertTrue(allocator.checkSkimCondition(address(pcvDeposit)));
        assertTrue(allocator.checkActionAllowed(address(pcvDeposit)));

        vm.expectRevert("ERC20Allocator: drip condition not met");
        allocator.drip(address(pcvDeposit));
    }

    function testDripFailsWhenBufferExhausted() public {
        vm.startPrank(addresses.governorAddress);
        core.grantPCVController(address(allocator));
        allocator.setBufferCap(uint128(targetBalance)); /// only allow 1 complete drip to exhaust buffer

        token.mint(address(pcvDeposit), targetBalance * 2);

        assertTrue(allocator.checkDripCondition(address(pcvDeposit)));
        assertTrue(!allocator.checkSkimCondition(address(pcvDeposit))); /// cannot skim
        assertTrue(allocator.checkActionAllowed(address(pcvDeposit)));

        allocator.drip(address(pcvDeposit));

        assertTrue(!allocator.checkDripCondition(address(pcvDeposit)));
        assertTrue(!allocator.checkSkimCondition(address(pcvDeposit))); /// cannot skim
        assertTrue(!allocator.checkActionAllowed(address(pcvDeposit)));
        assertEq(allocator.buffer(), 0);

        token.mint(address(psm), targetBalance);

        assertEq(psm.balance(), targetBalance * 2);
        assertTrue(allocator.checkSkimCondition(address(pcvDeposit)));
        assertTrue(allocator.checkActionAllowed(address(pcvDeposit)));
        assertTrue(!allocator.checkDripCondition(address(pcvDeposit))); /// cannot drip as buffer is exhausted

        token.mockBurn(address(psm), token.balanceOf(address(psm)));
        assertEq(allocator.buffer(), 0);

        vm.expectRevert("RateLimited: no rate limit buffer");
        allocator.drip(address(pcvDeposit));
    }

    function testDripFailsWhenBufferZero() public {
        vm.startPrank(addresses.governorAddress);
        core.grantPCVController(address(allocator));
        allocator.setBufferCap(uint128(0)); /// fully exhaust buffer

        token.mint(address(pcvDeposit), targetBalance * 2);

        assertTrue(!allocator.checkDripCondition(address(pcvDeposit)));
        assertTrue(!allocator.checkSkimCondition(address(pcvDeposit))); /// cannot skim
        assertTrue(!allocator.checkActionAllowed(address(pcvDeposit)));
        assertEq(allocator.buffer(), 0);

        vm.expectRevert("RateLimited: no rate limit buffer");
        allocator.drip(address(pcvDeposit));
    }

    function testDripSucceedsWhenBufferFiftyPercentDepleted() public {
        vm.startPrank(addresses.governorAddress);
        core.grantPCVController(address(allocator));
        allocator.setBufferCap(uint128(targetBalance / 2)); /// halfway exhaust buffer

        token.mint(address(pcvDeposit), targetBalance * 2);

        assertTrue(allocator.checkDripCondition(address(pcvDeposit)));
        assertTrue(!allocator.checkSkimCondition(address(pcvDeposit))); /// cannot skim
        assertTrue(allocator.checkActionAllowed(address(pcvDeposit)));
        assertEq(allocator.buffer(), targetBalance / 2);

        allocator.drip(address(pcvDeposit));

        assertEq(psm.balance(), targetBalance / 2);
    }

    function testDripSucceedsWhenBufferFiftyPercentDepletedDecimalsNormalized()
        public
    {
        int8 decimalsNormalizer = 12; /// scale up new token by 12 decimals
        uint248 newTargetBalance = 100_000e6; /// target balance 100k

        MockERC20 newToken = new MockERC20();
        ERC20HoldingPCVDeposit newPsm = new ERC20HoldingPCVDeposit(
            address(core),
            IERC20(address(newToken)),
            address(0)
        );
        ERC20HoldingPCVDeposit newPcvDeposit = new ERC20HoldingPCVDeposit(
            address(core),
            IERC20(address(newToken)),
            address(0)
        );

        vm.startPrank(addresses.governorAddress);
        allocator.connectPSM(
            address(newPsm),
            newTargetBalance,
            decimalsNormalizer
        );
        allocator.connectDeposit(address(newPsm), address(newPcvDeposit));
        vm.stopPrank();

        vm.startPrank(addresses.governorAddress);
        core.grantPCVController(address(allocator));
        allocator.setBufferCap(uint128(targetBalance / 2)); /// halfway exhaust buffer

        newToken.mint(address(newPcvDeposit), newTargetBalance * 2);

        assertTrue(allocator.checkDripCondition(address(newPcvDeposit)));
        assertTrue(!allocator.checkSkimCondition(address(newPcvDeposit))); /// cannot skim
        assertTrue(allocator.checkActionAllowed(address(newPcvDeposit)));
        assertEq(allocator.buffer(), targetBalance / 2);

        (uint256 amountToDrip, uint256 adjustedAmountToDrip) = allocator
            .getDripDetails(
                address(newPsm),
                PCVDeposit(address(newPcvDeposit))
            );

        allocator.drip(address(newPcvDeposit));

        assertEq(adjustedAmountToDrip, amountToDrip * 1e12);
        assertEq(newPsm.balance(), amountToDrip);
        assertEq(newPsm.balance(), newTargetBalance / 2);
        assertEq(allocator.buffer(), 0);
    }

    function testDripSucceedsWhenBufferFiftyPercentDepletedDecimalsNormalizedNegative()
        public
    {
        int8 decimalsNormalizer = -12; /// scale down new token by 12 decimals
        uint248 newTargetBalance = 100_000e30; /// target balance 100k

        MockERC20 newToken = new MockERC20();
        ERC20HoldingPCVDeposit newPsm = new ERC20HoldingPCVDeposit(
            address(core),
            IERC20(address(newToken)),
            address(0)
        );
        ERC20HoldingPCVDeposit newPcvDeposit = new ERC20HoldingPCVDeposit(
            address(core),
            IERC20(address(newToken)),
            address(0)
        );

        vm.startPrank(addresses.governorAddress);
        allocator.connectPSM(
            address(newPsm),
            newTargetBalance,
            decimalsNormalizer
        );
        allocator.connectDeposit(address(newPsm), address(newPcvDeposit));
        vm.stopPrank();

        vm.startPrank(addresses.governorAddress);
        core.grantPCVController(address(allocator));
        allocator.setBufferCap(uint128(targetBalance / 2)); /// halfway exhaust buffer

        newToken.mint(address(newPcvDeposit), newTargetBalance * 2);

        assertTrue(allocator.checkDripCondition(address(newPcvDeposit)));
        assertTrue(!allocator.checkSkimCondition(address(newPcvDeposit))); /// cannot skim
        assertTrue(allocator.checkActionAllowed(address(newPcvDeposit)));
        assertEq(allocator.buffer(), targetBalance / 2);

        (uint256 amountToDrip, uint256 adjustedAmountToDrip) = allocator
            .getDripDetails(
                address(newPsm),
                PCVDeposit(address(newPcvDeposit))
            );

        allocator.drip(address(newPcvDeposit));

        assertEq(adjustedAmountToDrip, amountToDrip / 1e12);
        assertEq(newPsm.balance(), amountToDrip);
        assertEq(newPsm.balance(), newTargetBalance / 2);
        assertEq(allocator.buffer(), 0); /// buffer has been fully drained
    }

    function testCreateDepositNonGovFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        allocator.connectPSM(address(0), 0, 0);
    }

    function testeditPSMTargetBalanceNonGovFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        allocator.editPSMTargetBalance(address(0), 0);
    }

    function testConnectDepositNonGovFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        allocator.connectDeposit(address(0), address(0)); /// params don't matter as call reverts
    }

    function testDeleteDepositNonGovFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        allocator.deleteDeposit(address(0));
    }

    function testDeletePSMNonGovFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        allocator.disconnectPSM(address(psm));
    }

    function _disconnectPSM() internal {
        vm.prank(addresses.governorAddress);
        vm.expectEmit(true, false, false, true, address(allocator));
        emit PSMDeleted(address(psm));
        allocator.disconnectPSM(address(psm));

        (
            address psmToken,
            uint248 psmTargetBalance,
            int8 decimalsNormalizer
        ) = allocator.allPSMs(address(psm));
        /// this part of the mapping doesn't get deleted when PSM is deleted
        address psmAddress = allocator.pcvDepositToPSM(address(pcvDeposit));

        assertEq(psmTargetBalance, 0);
        assertEq(decimalsNormalizer, 0);
        assertEq(psmToken, address(0));
        assertEq(psmAddress, address(psm));
    }

    function testDeletePSMGovSucceeds() public {
        _disconnectPSM();
    }

    /// test that you can no longer skim to this psm when pcv deposits
    /// are still connected to a non existent psm
    function testDeletePSMGovSucceedsSkimFails() public {
        _disconnectPSM();

        vm.expectRevert();
        allocator.skim(address(pcvDeposit));
    }

    /// test that you can no longer drip to this psm when pcv deposits
    /// are still connected to a non existent psm
    function testDeletePSMGovSucceedsDripFails() public {
        _disconnectPSM();

        vm.expectRevert();
        allocator.drip(address(pcvDeposit));
    }

    /// test that you can no longer skim to this psm when pcv deposits
    /// are not connected to a non existent psm
    function testDeletePSMGovSucceedsSkimFailsDeleteDeposit() public {
        _disconnectPSM();
        vm.prank(addresses.governorAddress);
        allocator.deleteDeposit(address(pcvDeposit));

        /// connection broken
        address psmAddress = allocator.pcvDepositToPSM(address(pcvDeposit));
        assertEq(psmAddress, address(0));

        vm.expectRevert("ERC20Allocator: invalid PCVDeposit");
        allocator.skim(address(pcvDeposit));
    }

    /// test that you can no longer drip to this psm when pcv deposits
    /// are not connected to a non existent psm
    function testDeletePSMGovSucceedsDripFailsDeleteDeposit() public {
        _disconnectPSM();
        vm.prank(addresses.governorAddress);
        allocator.deleteDeposit(address(pcvDeposit));

        vm.expectRevert("ERC20Allocator: invalid PCVDeposit");
        allocator.drip(address(pcvDeposit));
    }

    function testDeleteDepositGovSucceeds() public {
        vm.prank(addresses.governorAddress);
        vm.expectEmit(true, false, false, true, address(allocator));
        emit DepositDeleted(address(pcvDeposit));
        allocator.deleteDeposit(address(pcvDeposit));

        address psmDeposit = allocator.pcvDepositToPSM(address(psm));
        assertEq(psmDeposit, address(0));
    }

    function testDripAndSkimFailsWhenPaused() public {
        vm.prank(addresses.governorAddress);
        allocator.pause();

        vm.expectRevert("Pausable: paused");
        allocator.skim(address(pcvDeposit));

        vm.expectRevert("Pausable: paused");
        allocator.drip(address(pcvDeposit));
    }

    function testSkimFailsWhenOverTargetWithoutPCVController() public {
        uint256 depositBalance = 10_000_000e18;

        token.mint(address(psm), depositBalance);

        vm.expectRevert("UNAUTHORIZED");
        allocator.skim(address(pcvDeposit));
    }

    function testDripperFailsWhenUnderFunded() public {
        assertTrue(!allocator.checkActionAllowed(address(pcvDeposit)));
        assertTrue(!allocator.checkDripCondition(address(pcvDeposit)));
        assertTrue(!allocator.checkSkimCondition(address(pcvDeposit)));

        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(allocator));

        vm.expectRevert("ERC20Allocator: drip condition not met");
        allocator.drip(address(pcvDeposit));
    }

    function testDripNoOpWhenUnderTargetWithoutPCVControllerRole() public {
        assertTrue(!allocator.checkActionAllowed(address(pcvDeposit)));
        assertTrue(!allocator.checkDripCondition(address(pcvDeposit)));
        assertTrue(!allocator.checkSkimCondition(address(pcvDeposit)));

        vm.expectRevert("ERC20Allocator: drip condition not met");
        allocator.drip(address(pcvDeposit));
    }

    function testDripFailsWhenUnderTargetWithoutPCVControllerRole() public {
        token.mint(address(pcvDeposit), 1); /// with a balance of 1, the drip action is valid

        assertTrue(allocator.checkActionAllowed(address(pcvDeposit)));
        assertTrue(allocator.checkDripCondition(address(pcvDeposit)));
        assertTrue(!allocator.checkSkimCondition(address(pcvDeposit)));

        vm.expectRevert("UNAUTHORIZED");
        allocator.drip(address(pcvDeposit));
    }

    function testDoActionNoOpWhenUnderTargetWithoutPCVControllerRole() public {
        /// if this action was valid, it would fail because it doesn't have the pcv controller role
        allocator.doAction(address(pcvDeposit));
    }

    function testDoActionFailsWhenUnderTargetWithoutPCVControllerRole() public {
        token.mint(address(pcvDeposit), 1); /// with a balance of 1, the drip action is valid
        assertTrue(allocator.checkActionAllowed(address(pcvDeposit)));
        assertTrue(allocator.checkDripCondition(address(pcvDeposit)));
        vm.expectRevert("UNAUTHORIZED");
        allocator.doAction(address(pcvDeposit));
    }

    function testTargetBalanceGovSucceeds() public {
        uint248 newThreshold = 10_000_000e18;
        vm.expectEmit(false, false, false, true, address(allocator));
        emit PSMTargetBalanceUpdated(address(psm), newThreshold);
        vm.prank(addresses.governorAddress);
        allocator.editPSMTargetBalance(address(psm), newThreshold);
        assertEq(uint256(newThreshold), allocator.targetBalance(address(psm)));
    }

    function testSweepGovSucceeds() public {
        uint256 mintAmount = 100_000_000e18;
        token.mint(address(allocator), mintAmount);
        vm.prank(addresses.governorAddress);
        allocator.sweep(address(token), address(this), mintAmount);
        assertEq(token.balanceOf(address(this)), mintAmount);
    }

    function testSweepNonGovFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        allocator.sweep(address(token), address(this), 0);
    }

    function testPullSucceedsWhenOverThresholdWithPCVController() public {
        uint256 depositBalance = 10_000_000e18;

        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(allocator));

        token.mint(address(psm), depositBalance);

        assertTrue(allocator.checkSkimCondition(address(pcvDeposit)));
        allocator.skim(address(pcvDeposit));
        assertTrue(!allocator.checkSkimCondition(address(pcvDeposit)));

        assertEq(token.balanceOf(address(psm)), targetBalance);
        assertEq(
            token.balanceOf(address(pcvDeposit)),
            depositBalance - targetBalance
        );
    }

    function testDripSucceedsWhenOverThreshold() public {
        uint256 depositBalance = 10_000_000e18;

        token.mint(address(pcvDeposit), depositBalance);

        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(allocator));
        allocator.drip(address(pcvDeposit));

        assertEq(
            token.balanceOf(address(pcvDeposit)),
            depositBalance - targetBalance
        );
        assertEq(token.balanceOf(address(psm)), targetBalance);
    }

    function testDripSucceedsWhenOverThresholdAndPSMPartiallyFunded() public {
        uint256 depositBalance = 10_000_000e18;
        uint256 bufferStart = allocator.buffer();

        token.mint(address(pcvDeposit), depositBalance);
        token.mint(address(psm), targetBalance / 2);

        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(allocator));

        vm.prank(addresses.governorAddress);
        allocator.pause();

        /// actions not allowed while paused
        assertTrue(!allocator.checkActionAllowed(address(pcvDeposit)));

        vm.prank(addresses.governorAddress);
        allocator.unpause();

        assertTrue(allocator.checkActionAllowed(address(pcvDeposit)));

        allocator.drip(address(pcvDeposit));
        assertTrue(!allocator.checkDripCondition(address(pcvDeposit)));
        assertTrue(!allocator.checkActionAllowed(address(pcvDeposit)));

        uint256 bufferEnd = allocator.buffer();

        assertEq(bufferEnd, bufferStart - targetBalance / 2);
        assertEq(bufferStart, uint256(bufferCap));
        assertEq(
            token.balanceOf(address(pcvDeposit)),
            depositBalance - targetBalance / 2
        );
        assertEq(token.balanceOf(address(psm)), targetBalance);
    }

    function testAllConditionsFalseWhenPaused() public {
        uint256 depositBalance = 10_000_000e18;

        token.mint(address(pcvDeposit), depositBalance);
        token.mint(address(psm), targetBalance / 2);

        /// drip condition becomes false when contract is paused
        assertTrue(allocator.checkDripCondition(address(pcvDeposit)));

        vm.prank(addresses.governorAddress);
        allocator.pause();

        /// actions not allowed while paused
        assertTrue(!allocator.checkDripCondition(address(pcvDeposit)));
        assertTrue(!allocator.checkActionAllowed(address(pcvDeposit)));
        assertTrue(!allocator.checkSkimCondition(address(pcvDeposit)));
    }

    function testBufferUpdatesCorrectly() public {
        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(allocator));

        token.mint(address(pcvDeposit), targetBalance);
        token.mint(address(psm), targetBalance / 2);
        assertTrue(allocator.checkActionAllowed(address(pcvDeposit)));
        assertTrue(allocator.checkDripCondition(address(pcvDeposit)));
        assertTrue(!allocator.checkSkimCondition(address(pcvDeposit))); /// psm balance empty, cannot skim

        allocator.drip(address(pcvDeposit));

        uint256 bufferEnd = allocator.buffer();
        token.mint(address(psm), targetBalance);

        allocator.skim(address(pcvDeposit));

        uint256 bufferEndAfterSkim = allocator.buffer();
        assertEq(bufferEndAfterSkim, bufferCap);
        assertEq(bufferEnd, bufferCap - targetBalance / 2);
    }

    function testBufferDepletesAndReplenishesCorrectly() public {
        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(allocator));

        token.mint(address(pcvDeposit), targetBalance);
        token.mint(address(psm), targetBalance / 2);

        assertTrue(allocator.checkActionAllowed(address(pcvDeposit)));
        assertTrue(allocator.checkDripCondition(address(pcvDeposit)));

        allocator.drip(address(pcvDeposit));

        uint256 bufferEnd = allocator.buffer();
        assertEq(bufferEnd, bufferCap - targetBalance / 2);
        /// multiply by 2 to get over buffer cap and fully replenish buffer
        uint256 skimAmount = (bufferCap - bufferEnd) * 2;
        token.mint(address(psm), (targetBalance * 3) / 2);

        assertTrue(allocator.checkSkimCondition(address(pcvDeposit)));

        allocator.skim(address(pcvDeposit));

        uint256 bufferEndAfterSkim = allocator.buffer();
        assertEq(bufferEndAfterSkim, bufferCap);
    }

    /// test a new deposit with decimal normalization
    function testBufferDepletesAndReplenishesCorrectlyMultipleDecimalNormalizedDeposits()
        public
    {
        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(allocator));

        int8 decimalsNormalizer = 12; /// scale up new token by 12 decimals
        uint256 scalingFactor = 1e12; /// scaling factor of 1e12 upwards
        uint248 newTargetBalance = 100_000e6; /// target balance 100k

        MockERC20 newToken = new MockERC20();
        ERC20HoldingPCVDeposit newPsm = new ERC20HoldingPCVDeposit(
            address(core),
            IERC20(address(newToken)),
            address(0)
        );
        ERC20HoldingPCVDeposit newPcvDeposit = new ERC20HoldingPCVDeposit(
            address(core),
            IERC20(address(newToken)),
            address(0)
        );

        vm.startPrank(addresses.governorAddress);
        allocator.connectPSM(
            address(newPsm),
            newTargetBalance,
            decimalsNormalizer
        );
        allocator.connectDeposit(address(newPsm), address(newPcvDeposit));
        vm.stopPrank();

        (
            address psmToken,
            uint248 psmTargetBalance,
            int8 _decimalsNormalizer
        ) = allocator.allPSMs(address(newPsm));
        address _newPsm = allocator.pcvDepositToPSM(address(newPcvDeposit));

        /// assert new PSM has been properly wired into the allocator
        assertEq(psmTargetBalance, newTargetBalance);
        assertEq(decimalsNormalizer, _decimalsNormalizer);
        assertEq(psmToken, address(newToken));
        assertEq(address(_newPsm), address(newPsm));

        assertTrue(!allocator.checkDripCondition(address(newPcvDeposit))); /// drip action not allowed, due to 0 balance
        assertTrue(!allocator.checkDripCondition(address(pcvDeposit))); /// drip action not allowed, due to 0 balance

        {
            (
                uint256 psmAmountToDrip,
                uint256 psmAdjustedAmountToDrip
            ) = allocator.getDripDetails(
                    address(psm),
                    PCVDeposit(address(pcvDeposit))
                );

            (
                uint256 newPsmAmountToDrip,
                uint256 newPsmAdjustedAmountToDrip
            ) = allocator.getDripDetails(
                    address(newPsm),
                    PCVDeposit(address(newPcvDeposit))
                );

            /// drips are 0 because pcv deposits are not funded

            assertEq(psmAmountToDrip, 0);
            assertEq(newPsmAmountToDrip, 0);

            assertEq(psmAdjustedAmountToDrip, 0);
            assertEq(newPsmAdjustedAmountToDrip, 0);
        }

        token.mint(address(pcvDeposit), targetBalance);
        newToken.mint(address(newPcvDeposit), newTargetBalance);

        {
            (
                uint256 psmAmountToDrip,
                uint256 psmAdjustedAmountToDrip
            ) = allocator.getDripDetails(
                    address(psm),
                    PCVDeposit(address(pcvDeposit))
                );

            (
                uint256 newPsmAmountToDrip,
                uint256 newPsmAdjustedAmountToDrip
            ) = allocator.getDripDetails(
                    address(newPsm),
                    PCVDeposit(address(newPcvDeposit))
                );

            assertEq(psmAmountToDrip, targetBalance);
            assertEq(newPsmAmountToDrip, newTargetBalance);

            assertEq(psmAdjustedAmountToDrip, targetBalance);
            assertEq(newPsmAdjustedAmountToDrip, targetBalance); /// adjusted amount equals target balance
        }

        assertTrue(allocator.checkActionAllowed(address(pcvDeposit)));
        assertTrue(allocator.checkDripCondition(address(pcvDeposit))); /// drip action allowed, and balance to do it
        assertTrue(!allocator.checkSkimCondition(address(pcvDeposit))); /// nothing to skim, balance is empty

        /// new PSM
        assertTrue(allocator.checkActionAllowed(address(newPcvDeposit)));
        assertTrue(allocator.checkDripCondition(address(newPcvDeposit))); /// drip action allowed, and balance to do it
        assertTrue(!allocator.checkSkimCondition(address(newPcvDeposit))); /// nothing to skim, balance is empty

        {
            uint256 startingBalancePcvDeposit = token.balanceOf(
                address(pcvDeposit)
            );
            uint256 startingBalanceNewPcvDeposit = newToken.balanceOf(
                address(newPcvDeposit)
            );

            allocator.drip(address(pcvDeposit));
            allocator.drip(address(newPcvDeposit));

            uint256 endingBalancePsm = token.balanceOf(address(psm));
            uint256 endingBalanceNewPsm = newToken.balanceOf(address(newPsm));
            uint256 endingBalancePcvDeposit = token.balanceOf(
                address(pcvDeposit)
            );
            uint256 endingBalanceNewPcvDeposit = newToken.balanceOf(
                address(newPcvDeposit)
            );

            assertEq(startingBalancePcvDeposit, targetBalance);
            assertEq(startingBalanceNewPcvDeposit, newTargetBalance);

            assertEq(endingBalancePsm, targetBalance);
            assertEq(endingBalanceNewPsm, newTargetBalance);

            /// both of these should be zero'd out
            assertEq(endingBalancePcvDeposit, 0);
            assertEq(endingBalanceNewPcvDeposit, 0);
        }

        assertEq(token.balanceOf(address(psm)), targetBalance);
        assertEq(newToken.balanceOf(address(newPsm)), newTargetBalance);

        uint256 bufferEnd = allocator.buffer();
        assertEq(bufferEnd, bufferCap - targetBalance * 2); /// should have effectively dripped target balance 2x, meaning normalization worked properly

        /// multiply by 2 to get over buffer cap and fully replenish buffer
        uint256 skimAmount = bufferCap - bufferEnd;
        token.mint(address(psm), skimAmount);
        newToken.mint(address(newPsm), skimAmount / scalingFactor); /// divide by scaling factor as new token only has 6 decimals

        {
            (uint256 psmAmountToSkim, uint256 adjustedAmountToSkim) = allocator
                .getSkimDetails(address(pcvDeposit));

            assertEq(psmAmountToSkim, skimAmount);
            assertEq(adjustedAmountToSkim, skimAmount);

            allocator.skim(address(pcvDeposit));
        }

        {
            (uint256 psmAmountToSkim, uint256 adjustedAmountToSkim) = allocator
                .getSkimDetails(address(newPcvDeposit));

            assertEq(psmAmountToSkim, skimAmount / scalingFactor); /// actual amount is scaled up by 1e6
            assertEq(adjustedAmountToSkim, psmAmountToSkim * scalingFactor); /// adjusted amount is scaled up by 1e18 after scaling factor is applied
            allocator.skim(address(newPcvDeposit));
        }

        assertEq(token.balanceOf(address(psm)), targetBalance);
        assertEq(newToken.balanceOf(address(newPsm)), newTargetBalance);

        uint256 bufferEndAfterSkim = allocator.buffer();
        assertEq(bufferEndAfterSkim, bufferCap); /// fully replenish buffer, meaning normalization worked properly
    }

    function testDripSucceedsWhenUnderFullTargetBalance(
        uint8 denominator
    ) public {
        vm.assume(denominator > 1);
        uint256 depositBalance = targetBalance / denominator;

        token.mint(address(pcvDeposit), depositBalance);

        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(allocator));

        allocator.drip(address(pcvDeposit));

        assertEq(token.balanceOf(address(pcvDeposit)), 0);
        assertEq(token.balanceOf(address(psm)), depositBalance);
    }

    function testSkimSucceedsWhenOverThresholdWithPCVControllerFuzz(
        uint128 depositBalance
    ) public {
        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(allocator));
        token.mint(address(psm), depositBalance);

        if (depositBalance > targetBalance) {
            assertTrue(allocator.checkSkimCondition(address(pcvDeposit)));

            allocator.skim(address(pcvDeposit));

            assertTrue(!allocator.checkSkimCondition(address(pcvDeposit)));
            assertEq(token.balanceOf(address(psm)), targetBalance);
            assertEq(
                token.balanceOf(address(pcvDeposit)),
                depositBalance - targetBalance
            );
        } else {
            vm.expectRevert("ERC20Allocator: skim condition not met");
            allocator.skim(address(pcvDeposit));
        }
    }

    function testDoActionDripSucceedsWhenUnderFullTargetBalance(
        uint8 denominator
    ) public {
        vm.assume(denominator > 1);
        uint256 depositBalance = targetBalance / denominator;

        token.mint(address(pcvDeposit), depositBalance);

        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(allocator));

        uint256 bufferStart = allocator.buffer();
        (uint256 amountToDrip, uint256 adjustedAmountToDrip) = allocator
            .getDripDetails(address(psm), PCVDeposit(address(pcvDeposit)));

        /// this has to be true
        assertTrue(allocator.checkDripCondition(address(pcvDeposit)));

        allocator.doAction(address(pcvDeposit));

        if (token.balanceOf(address(psm)) >= targetBalance) {
            assertTrue(!allocator.checkDripCondition(address(pcvDeposit)));
        }

        assertEq(bufferStart, allocator.buffer() + adjustedAmountToDrip);
        assertEq(amountToDrip, adjustedAmountToDrip);
        assertEq(token.balanceOf(address(pcvDeposit)), 0);
        assertEq(token.balanceOf(address(psm)), depositBalance);
    }

    function testDoActionSkimSucceedsWhenOverThresholdWithPCVControllerFuzz(
        uint128 depositBalance
    ) public {
        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(allocator));
        token.mint(address(psm), depositBalance);

        if (depositBalance > targetBalance) {
            uint256 bufferStart = allocator.buffer();
            allocator.doAction(address(pcvDeposit));

            assertEq(bufferStart, allocator.buffer());
            assertEq(token.balanceOf(address(psm)), targetBalance);
            assertEq(
                token.balanceOf(address(pcvDeposit)),
                depositBalance - targetBalance
            );
        }
    }

    /// tests where non whitelisted psm actions drip, skim and doAction fail

    function testDripFailsOnNonWhitelistedPSM() public {
        address nonWhitelistedPSM = address(1);
        (
            address psmToken,
            uint248 psmTargetBalance,
            int8 decimalsNormalizer
        ) = allocator.allPSMs(nonWhitelistedPSM);
        address psmPcvDeposit = allocator.pcvDepositToPSM(nonWhitelistedPSM);

        assertEq(psmTargetBalance, 0);
        assertEq(decimalsNormalizer, 0);
        assertEq(psmToken, address(0));
        assertEq(psmPcvDeposit, address(0));

        /// points to token address 0, thus reverting in check drip condition
        vm.expectRevert("ERC20Allocator: invalid PCVDeposit");
        allocator.drip(address(nonWhitelistedPSM));
    }

    function testSkimFailsOnNonWhitelistedPSM() public {
        address nonWhitelistedPSM = address(1);
        (
            address psmToken,
            uint248 psmTargetBalance,
            int8 decimalsNormalizer
        ) = allocator.allPSMs(nonWhitelistedPSM);
        address psmPcvDeposit = allocator.pcvDepositToPSM(nonWhitelistedPSM);

        assertEq(psmTargetBalance, 0);
        assertEq(decimalsNormalizer, 0);
        assertEq(psmToken, address(0));
        assertEq(psmPcvDeposit, address(0));

        /// points to token address 0, thus reverting in check skim condition
        vm.expectRevert("ERC20Allocator: invalid PCVDeposit");
        allocator.skim(address(nonWhitelistedPSM));
    }

    function testDoActionNoOpOnNonWhitelistedPSM() public {
        address nonWhitelistedPSM = address(1);
        (
            address psmToken,
            uint248 psmTargetBalance,
            int8 decimalsNormalizer
        ) = allocator.allPSMs(nonWhitelistedPSM);
        address psmPcvDeposit = allocator.pcvDepositToPSM(nonWhitelistedPSM);

        assertEq(psmTargetBalance, 0);
        assertEq(decimalsNormalizer, 0);
        assertEq(psmToken, address(0));
        assertEq(psmPcvDeposit, address(0));

        /// points to token address 0, thus reverting in check drip condition
        vm.expectRevert("ERC20Allocator: invalid PCVDeposit");
        allocator.doAction(address(nonWhitelistedPSM));
    }

    /// pure view only functions

    function testGetAdjustedAmountUp(uint128 amount) public {
        int8 decimalsNormalizer = 18; /// add on 18 decimals
        uint256 adjustedAmount = allocator.getAdjustedAmount(
            amount,
            decimalsNormalizer
        );
        uint256 actualAmount = amount; /// cast up to avoid overflow
        assertEq(adjustedAmount, actualAmount * 1e18);
    }

    function testGetAdjustedAmountDown(uint128 amount) public {
        int8 decimalsNormalizer = -18; /// remove 18 decimals
        uint256 adjustedAmount = allocator.getAdjustedAmount(
            amount,
            decimalsNormalizer
        );
        assertEq(adjustedAmount, amount / 1e18);
    }
}
