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
    event DepositUpdated(
        address psm,
        address pcvDeposit,
        address token,
        uint248 targetBalance,
        int8 decimalsNormalizer
    );

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
            IERC20(address(token))
        );

        psm = new ERC20HoldingPCVDeposit(address(core), IERC20(address(token)));

        allocator = new ERC20Allocator(
            address(core),
            maxRateLimitPerSecond,
            rateLimitPerSecond,
            bufferCap
        );

        vm.prank(addresses.governorAddress);
        allocator.createDeposit(
            address(psm),
            address(pcvDeposit),
            targetBalance,
            0
        );
    }

    function testSetup() public {
        assertEq(address(allocator.core()), address(core));
        (
            address psmPcvDeposit,
            address psmToken,
            uint248 psmTargetBalance,
            int8 decimalsNormalizer
        ) = allocator.allDeposits(address(psm));

        assertEq(psmTargetBalance, targetBalance);
        assertEq(decimalsNormalizer, 0);
        assertEq(psmToken, address(token));
        assertEq(psmPcvDeposit, address(pcvDeposit));
        assertEq(allocator.buffer(), bufferCap);

        assertTrue(!allocator.checkDripCondition(address(psm))); /// drip action not allowed, due to 0 balance
        assertTrue(!allocator.checkSkimCondition(address(psm))); /// skim action not allowed, not over threshold
        assertTrue(!allocator.checkActionAllowed(address(psm))); /// neither drip nor skim action allowed
    }

    function testSkimFailsWhenUnderFunded() public {
        assertTrue(!allocator.checkSkimCondition(address(psm)));
        assertTrue(!allocator.checkDripCondition(address(psm))); /// drip action not allowed, due to 0 balance
        assertTrue(!allocator.checkActionAllowed(address(psm)));

        vm.expectRevert("ERC20Allocator: skim condition not met");
        allocator.skim(address(psm));
    }

    function testDripFailsWhenUnderFunded() public {
        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(allocator));
        token.mint(address(psm), targetBalance * 2);

        assertTrue(!allocator.checkDripCondition(address(psm)));
        assertTrue(allocator.checkSkimCondition(address(psm)));
        assertTrue(allocator.checkActionAllowed(address(psm)));

        vm.expectRevert("ERC20Allocator: drip condition not met");
        allocator.drip(address(psm));
    }

    function testDripFailsWhenBufferExhausted() public {
        vm.startPrank(addresses.governorAddress);
        core.grantPCVController(address(allocator));
        allocator.setBufferCap(uint128(targetBalance)); /// only allow 1 complete drip to exhaust buffer

        token.mint(address(pcvDeposit), targetBalance * 2);

        assertTrue(allocator.checkDripCondition(address(psm)));
        assertTrue(!allocator.checkSkimCondition(address(psm))); /// cannot skim
        assertTrue(allocator.checkActionAllowed(address(psm)));

        allocator.drip(address(psm));

        assertTrue(!allocator.checkDripCondition(address(psm)));
        assertTrue(!allocator.checkSkimCondition(address(psm))); /// cannot skim
        assertTrue(!allocator.checkActionAllowed(address(psm)));
        assertEq(allocator.buffer(), 0);
    }

    function testDripFailsWhenBufferZero() public {
        vm.startPrank(addresses.governorAddress);
        core.grantPCVController(address(allocator));
        allocator.setBufferCap(uint128(0)); /// fully exhaust buffer

        token.mint(address(pcvDeposit), targetBalance * 2);

        assertTrue(!allocator.checkDripCondition(address(psm)));
        assertTrue(!allocator.checkSkimCondition(address(psm))); /// cannot skim
        assertTrue(!allocator.checkActionAllowed(address(psm)));
        assertEq(allocator.buffer(), 0);
    }

    function testCreateDepositNonGovFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        allocator.createDeposit(address(0), address(0), 0, 0);
    }

    function testEditDepositNonGovFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        allocator.editDeposit(address(0), address(0), 0, 0);
    }

    function testDeleteDepositNonGovFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        allocator.deleteDeposit(address(0));
    }

    function testDeleteDepositGovSucceeds() public {
        vm.prank(addresses.governorAddress);
        vm.expectEmit(true, false, false, true, address(allocator));
        emit DepositDeleted(address(psm));
        allocator.deleteDeposit(address(psm));

        (
            address psmPcvDeposit,
            address psmToken,
            uint248 psmTargetBalance,
            int8 decimalsNormalizer
        ) = allocator.allDeposits(address(psm));

        assertEq(psmTargetBalance, 0);
        assertEq(decimalsNormalizer, 0);
        assertEq(psmToken, address(0));
        assertEq(psmPcvDeposit, address(0));
    }

    function testDripAndSkimFailsWhenPaused() public {
        vm.prank(addresses.governorAddress);
        allocator.pause();

        vm.expectRevert("Pausable: paused");
        allocator.skim(address(psm));

        vm.expectRevert("Pausable: paused");
        allocator.drip(address(psm));
    }

    function testSkimFailsWhenOverTargetWithoutPCVController() public {
        uint256 depositBalance = 10_000_000e18;

        token.mint(address(psm), depositBalance);

        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        allocator.skim(address(psm));
    }

    function testDripperFailsWhenUnderFunded() public {
        assertTrue(!allocator.checkActionAllowed(address(psm)));
        assertTrue(!allocator.checkDripCondition(address(psm)));
        assertTrue(!allocator.checkSkimCondition(address(psm)));

        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(allocator));

        vm.expectRevert("ERC20Allocator: drip condition not met");
        allocator.drip(address(psm));
    }

    function testDripNoOpWhenUnderTargetWithoutPCVControllerRole() public {
        assertTrue(!allocator.checkActionAllowed(address(psm)));
        assertTrue(!allocator.checkDripCondition(address(psm)));
        assertTrue(!allocator.checkSkimCondition(address(psm)));

        vm.expectRevert("ERC20Allocator: drip condition not met");
        allocator.drip(address(psm));
    }

    function testDripFailsWhenUnderTargetWithoutPCVControllerRole() public {
        token.mint(address(pcvDeposit), 1); /// with a balance of 1, the drip action is valid

        assertTrue(allocator.checkActionAllowed(address(psm)));
        assertTrue(allocator.checkDripCondition(address(psm)));
        assertTrue(!allocator.checkSkimCondition(address(psm)));

        vm.expectRevert("UNAUTHORIZED");
        allocator.drip(address(psm));
    }

    function testDoActionNoOpWhenUnderTargetWithoutPCVControllerRole() public {
        /// if this action was valid, it would fail because it doesn't have the pcv controller role
        allocator.doAction(address(psm));
    }

    function testDoActionFailsWhenUnderTargetWithoutPCVControllerRole() public {
        token.mint(address(pcvDeposit), 1); /// with a balance of 1, the drip action is valid
        assertTrue(allocator.checkActionAllowed(address(psm)));
        assertTrue(allocator.checkDripCondition(address(psm)));
        vm.expectRevert("UNAUTHORIZED");
        allocator.doAction(address(psm));
    }

    function testTargetBalanceGovSucceeds() public {
        uint248 newThreshold = 10_000_000e18;
        vm.expectEmit(false, false, false, true, address(allocator));
        emit DepositUpdated(
            address(psm),
            address(pcvDeposit),
            address(token),
            newThreshold,
            0
        );
        vm.prank(addresses.governorAddress);
        allocator.editDeposit(
            address(psm),
            address(pcvDeposit),
            newThreshold,
            0
        );
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

        assertTrue(allocator.checkSkimCondition(address(psm)));
        allocator.skim(address(psm));
        assertTrue(!allocator.checkSkimCondition(address(psm)));

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
        allocator.drip(address(psm));

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
        assertTrue(!allocator.checkActionAllowed(address(psm)));

        vm.prank(addresses.governorAddress);
        allocator.unpause();

        assertTrue(allocator.checkActionAllowed(address(psm)));

        allocator.drip(address(psm));
        assertTrue(!allocator.checkDripCondition(address(psm)));
        assertTrue(!allocator.checkActionAllowed(address(psm)));

        uint256 bufferEnd = allocator.buffer();

        assertEq(bufferEnd, bufferStart - targetBalance / 2);
        assertEq(bufferStart, uint256(bufferCap));
        assertEq(
            token.balanceOf(address(pcvDeposit)),
            depositBalance - targetBalance / 2
        );
        assertEq(token.balanceOf(address(psm)), targetBalance);
    }

    function testDripConditionFalseWhenPaused() public {
        uint256 depositBalance = 10_000_000e18;

        token.mint(address(pcvDeposit), depositBalance);
        token.mint(address(psm), targetBalance / 2);

        /// drip condition becomes false when contract is paused
        assertTrue(allocator.checkDripCondition(address(psm)));

        vm.prank(addresses.governorAddress);
        allocator.pause();

        /// drip condition returns false when contract is paused
        assertTrue(!allocator.checkDripCondition(address(psm)));

        /// actions not allowed while paused
        assertTrue(!allocator.checkActionAllowed(address(psm)));
    }

    function testBufferUpdatesCorrectly() public {
        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(allocator));

        token.mint(address(pcvDeposit), targetBalance);
        token.mint(address(psm), targetBalance / 2);
        assertTrue(allocator.checkActionAllowed(address(psm)));
        assertTrue(allocator.checkDripCondition(address(psm)));

        allocator.drip(address(psm));

        uint256 bufferEnd = allocator.buffer();
        token.mint(address(psm), targetBalance);

        allocator.skim(address(psm));

        uint256 bufferEndAfterSkim = allocator.buffer();
        assertEq(bufferEndAfterSkim, bufferCap);
        assertEq(bufferEnd, bufferCap - targetBalance / 2);
    }

    function testBufferDepletesAndReplenishesCorrectly() public {
        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(allocator));

        token.mint(address(pcvDeposit), targetBalance);
        token.mint(address(psm), targetBalance / 2);
        assertTrue(allocator.checkActionAllowed(address(psm)));
        assertTrue(allocator.checkDripCondition(address(psm)));

        allocator.drip(address(psm));

        uint256 bufferEnd = allocator.buffer();
        assertEq(bufferEnd, bufferCap - targetBalance / 2);
        /// multiply by 2 to get over buffer cap and fully replenish buffer
        uint256 skimAmount = (bufferCap - bufferEnd) * 2;
        token.mint(address(psm), (targetBalance * 3) / 2);

        allocator.skim(address(psm));

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
            IERC20(address(newToken))
        );
        ERC20HoldingPCVDeposit newPcvDeposit = new ERC20HoldingPCVDeposit(
            address(core),
            IERC20(address(newToken))
        );

        vm.prank(addresses.governorAddress);
        allocator.createDeposit(
            address(newPsm),
            address(newPcvDeposit),
            newTargetBalance,
            decimalsNormalizer
        );

        (
            address psmPcvDeposit,
            address psmToken,
            uint248 psmTargetBalance,
            int8 _decimalsNormalizer
        ) = allocator.allDeposits(address(newPsm));

        /// assert new PSM has been properly wired into the allocator
        assertEq(psmTargetBalance, newTargetBalance);
        assertEq(decimalsNormalizer, _decimalsNormalizer);
        assertEq(psmToken, address(newToken));
        assertEq(psmPcvDeposit, address(newPcvDeposit));

        assertTrue(!allocator.checkDripCondition(address(newPsm))); /// drip action not allowed, due to 0 balance
        assertTrue(!allocator.checkDripCondition(address(psm))); /// drip action not allowed, due to 0 balance

        token.mint(address(pcvDeposit), targetBalance);
        newToken.mint(address(newPcvDeposit), targetBalance);

        assertTrue(allocator.checkActionAllowed(address(psm)));
        assertTrue(allocator.checkDripCondition(address(psm))); /// drip action allowed, and balance to do it
        assertTrue(!allocator.checkSkimCondition(address(psm))); /// nothing to skim, balance is empty

        /// new PSM
        assertTrue(allocator.checkActionAllowed(address(newPsm)));
        assertTrue(allocator.checkDripCondition(address(newPsm))); /// drip action allowed, and balance to do it
        assertTrue(!allocator.checkSkimCondition(address(newPsm))); /// nothing to skim, balance is empty

        allocator.drip(address(psm));
        allocator.drip(address(newPsm));

        assertEq(token.balanceOf(address(psm)), targetBalance);
        assertEq(newToken.balanceOf(address(newPsm)), newTargetBalance);

        uint256 bufferEnd = allocator.buffer();
        assertEq(bufferEnd, bufferCap - targetBalance * 2); /// should have effectively dripped target balance 2x, meaning normalization worked properly

        /// multiply by 2 to get over buffer cap and fully replenish buffer
        uint256 skimAmount = bufferCap - bufferEnd;
        token.mint(address(psm), skimAmount);
        newToken.mint(address(newPsm), skimAmount / scalingFactor); /// divide by scaling factor as new token only has 6 decimals

        /// scalingFactor
        allocator.skim(address(psm));
        allocator.skim(address(newPsm));

        assertEq(token.balanceOf(address(psm)), targetBalance);
        assertEq(newToken.balanceOf(address(newPsm)), newTargetBalance);

        uint256 bufferEndAfterSkim = allocator.buffer();
        assertEq(bufferEndAfterSkim, bufferCap); /// fully replenish buffer, meaning normalization worked properly
    }

    function testDripSucceedsWhenUnderFullTargetBalance(uint8 denominator)
        public
    {
        vm.assume(denominator > 1);
        uint256 depositBalance = targetBalance / denominator;

        token.mint(address(pcvDeposit), depositBalance);

        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(allocator));

        allocator.drip(address(psm));

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
            assertTrue(allocator.checkSkimCondition(address(psm)));

            allocator.skim(address(psm));

            assertTrue(!allocator.checkSkimCondition(address(psm)));
            assertEq(token.balanceOf(address(psm)), targetBalance);
            assertEq(
                token.balanceOf(address(pcvDeposit)),
                depositBalance - targetBalance
            );
        } else {
            vm.expectRevert("ERC20Allocator: skim condition not met");
            allocator.skim(address(psm));
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
        (
            uint256 amountToDrip,
            uint256 adjustedAmountToDrip,
            PCVDeposit target
        ) = allocator.getDripDetails(address(psm));

        /// this has to be true
        assertTrue(allocator.checkDripCondition(address(psm)));

        allocator.doAction(address(psm));

        if (token.balanceOf(address(psm)) >= targetBalance) {
            assertTrue(!allocator.checkDripCondition(address(psm)));
        }

        assertEq(bufferStart, allocator.buffer() + adjustedAmountToDrip);
        assertEq(amountToDrip, adjustedAmountToDrip);
        assertEq(address(target), address(pcvDeposit));
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
            allocator.doAction(address(psm));

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
            address psmPcvDeposit,
            address psmToken,
            uint248 psmTargetBalance,
            int8 decimalsNormalizer
        ) = allocator.allDeposits(nonWhitelistedPSM);

        assertEq(psmTargetBalance, 0);
        assertEq(decimalsNormalizer, 0);
        assertEq(psmToken, address(0));
        assertEq(psmPcvDeposit, address(0));

        /// points to token address 0, thus reverting in check drip condition
        vm.expectRevert();
        allocator.drip(address(nonWhitelistedPSM));
    }

    function testSkimFailsOnNonWhitelistedPSM() public {
        address nonWhitelistedPSM = address(1);
        (
            address psmPcvDeposit,
            address psmToken,
            uint248 psmTargetBalance,
            int8 decimalsNormalizer
        ) = allocator.allDeposits(nonWhitelistedPSM);

        assertEq(psmTargetBalance, 0);
        assertEq(decimalsNormalizer, 0);
        assertEq(psmToken, address(0));
        assertEq(psmPcvDeposit, address(0));

        /// points to token address 0, thus reverting in check skim condition
        vm.expectRevert();
        allocator.skim(address(nonWhitelistedPSM));
    }

    function testDoActionNoOpOnNonWhitelistedPSM() public {
        address nonWhitelistedPSM = address(1);
        (
            address psmPcvDeposit,
            address psmToken,
            uint248 psmTargetBalance,
            int8 decimalsNormalizer
        ) = allocator.allDeposits(nonWhitelistedPSM);

        assertEq(psmTargetBalance, 0);
        assertEq(decimalsNormalizer, 0);
        assertEq(psmToken, address(0));
        assertEq(psmPcvDeposit, address(0));

        /// points to token address 0, thus reverting in check drip condition
        vm.expectRevert();
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
        int8 decimalsNormalizer = -18; /// add on 18 decimals
        uint256 adjustedAmount = allocator.getAdjustedAmount(
            amount,
            decimalsNormalizer
        );
        assertEq(adjustedAmount, amount / 1e18);
    }
}
