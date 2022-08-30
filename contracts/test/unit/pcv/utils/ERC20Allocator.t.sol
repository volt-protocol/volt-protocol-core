pragma solidity =0.8.13;

import {Vm} from "./../../utils/Vm.sol";
import {ICore} from "../../../../core/ICore.sol";
import {DSTest} from "./../../utils/DSTest.sol";
import {MockERC20} from "../../../../mock/MockERC20.sol";
import {TribeRoles} from "../../../../core/TribeRoles.sol";
import {ERC20Allocator} from "../../../../pcv/utils/ERC20Allocator.sol";
import {PCVGuardAdmin} from "../../../../pcv/PCVGuardAdmin.sol";
import {ERC20HoldingPCVDeposit} from "../../../../pcv/ERC20HoldingPCVDeposit.sol";
import {getCore, getAddresses, VoltTestAddresses} from "./../../utils/Fixtures.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UnitTestERC20Allocator is DSTest {
    event TargetBalanceUpdate(uint256 oldThreshold, uint256 newThreshold);
    /// @notice event emitted when tokens are dripped
    event Dripped(uint256 amount);

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

    function testSkimFailsWhenUnderFunded() public {
        vm.expectRevert("ERC20Allocator: skim condition not met");
        allocator.skim(address(psm));
    }

    function testDripFailsWhenUnderFunded() public {
        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(allocator));
        token.mint(address(psm), targetBalance * 2);

        vm.expectRevert("ERC20Allocator: drip condition not met");
        allocator.drip(address(psm));
    }

    function testCreateDepositNonGovFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        allocator.createDeposit(address(0), address(0), 0, 0);
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

        vm.expectRevert("UNAUTHORIZED");
        allocator.skim(address(psm));
    }

    function testDripperFailsSilentlyWhenUnderFunded() public {
        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(allocator));

        vm.expectEmit(true, false, false, true, address(allocator));
        emit Dripped(0);
        allocator.drip(address(psm));
    }

    function testDripFailsWhenUnderTargetWithoutPCVControllerRole() public {
        vm.expectRevert("UNAUTHORIZED");
        allocator.drip(address(psm));
    }

    function testSetPullThresholdGovSucceeds() public {
        // uint256 newThreshold = 10_000_000e18;
        // vm.startPrank(addresses.governorAddress);
        // vm.expectEmit(true, false, false, true, address(allocator));
        // emit TargetBalanceUpdate(targetBalance, newThreshold);
        // allocator.setTargetBalance(newThreshold);
        // vm.stopPrank();
        // assertEq(newThreshold, allocator.targetBalance());
    }

    function testSweepGovSucceeds() public {}

    function testSweepNonGovFails() public {}

    function testPullSucceedsWhenOverThresholdWithPCVController() public {
        uint256 depositBalance = 10_000_000e18;

        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(allocator));

        token.mint(address(psm), depositBalance);
        allocator.skim(address(psm));

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
        allocator.drip(address(psm));

        uint256 bufferEnd = allocator.buffer();

        assertEq(bufferEnd, bufferStart - targetBalance / 2);
        assertEq(bufferStart, uint256(bufferCap));
        assertEq(
            token.balanceOf(address(pcvDeposit)),
            depositBalance - targetBalance / 2
        );
        assertEq(token.balanceOf(address(psm)), targetBalance);
    }

    function testBufferUpdatesCorrectly() public {
        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(allocator));

        token.mint(address(pcvDeposit), targetBalance);
        token.mint(address(psm), targetBalance / 2);

        allocator.drip(address(psm));

        uint256 bufferEnd = allocator.buffer();
        token.mint(address(psm), targetBalance);

        allocator.skim(address(psm));

        uint256 bufferEndAfterSkim = allocator.buffer();
        assertEq(bufferEndAfterSkim, bufferCap);
        assertEq(bufferEnd, bufferCap - targetBalance / 2);
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
            allocator.skim(address(psm));

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
}
