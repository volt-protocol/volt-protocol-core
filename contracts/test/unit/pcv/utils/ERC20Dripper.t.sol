pragma solidity =0.8.13;

import {Vm} from "./../../utils/Vm.sol";
import {ICore} from "../../../../core/ICore.sol";
import {DSTest} from "./../../utils/DSTest.sol";
import {MockERC20} from "../../../../mock/MockERC20.sol";
import {TribeRoles} from "../../../../core/TribeRoles.sol";
import {PCVDepositV2} from "../../../../pcv/PCVDepositV2.sol";
import {ERC20Dripper} from "../../../../pcv/utils/ERC20Dripper.sol";
import {PCVGuardAdmin} from "../../../../pcv/PCVGuardAdmin.sol";
import {ERC20HoldingPCVDeposit} from "../../../../pcv/ERC20HoldingPCVDeposit.sol";
import {getCore, getAddresses, VoltTestAddresses} from "./../../utils/Fixtures.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UnitTestERC20Dripper is DSTest {
    /// @notice event emitted when tokens are dripped
    event Dripped(uint256 amount);

    ICore private core;
    Vm public constant vm = Vm(HEVM_ADDRESS);
    VoltTestAddresses public addresses = getAddresses();

    /// @notice reference to the PCVDeposit to push to
    ERC20HoldingPCVDeposit private erc20HoldingDepositPush;

    /// @notice reference to the PCVDeposit to pull funds from
    ERC20HoldingPCVDeposit private erc20HoldingDepositPull;

    /// @notice reference to the ERC20
    ERC20Dripper private dripper;

    /// @notice token to push
    MockERC20 private token;

    /// @notice threshold over which to pull tokens from PCV deposit to target
    uint256 private constant dripThreshold = 100_000e18;

    /// @notice frequency of allowed drip
    uint256 private constant frequency = 1 days;

    function setUp() public {
        vm.warp(1); /// warp to 1 to allow init timed to work correctly

        core = getCore();
        token = new MockERC20();

        erc20HoldingDepositPush = new ERC20HoldingPCVDeposit(
            address(core),
            IERC20(address(token))
        );

        erc20HoldingDepositPull = new ERC20HoldingPCVDeposit(
            address(core),
            IERC20(address(token))
        );

        dripper = new ERC20Dripper(
            address(core),
            address(erc20HoldingDepositPush),
            frequency,
            dripThreshold,
            PCVDepositV2(address(erc20HoldingDepositPull))
        );

        /// dripper needs PCV Controller role to be able to pull funds
        /// from PCV deposits
        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(dripper));
    }

    function testDripperFailsSilentlyWhenUnderFunded() public {
        vm.warp(block.timestamp + dripper.duration());
        vm.expectEmit(true, false, false, true, address(dripper));
        emit Dripped(0);
        dripper.drip();
    }

    function testDripperFailsWithoutPCVControllerRole() public {
        vm.warp(block.timestamp + dripper.duration());
        vm.prank(addresses.governorAddress);
        core.revokePCVController(address(dripper));

        vm.expectRevert("UNAUTHORIZED");
        dripper.drip();
    }

    function testDripFailsWhenPaused() public {
        vm.prank(addresses.governorAddress);
        dripper.pause();
        vm.warp(block.timestamp + dripper.duration());

        vm.expectRevert("Pausable: paused");
        dripper.drip();
    }

    function testPullFailsWhenTimeNotPassed() public {
        vm.expectRevert("Timed: time not ended");
        dripper.drip();
    }

    function testPullSucceedsWhenOverThresholdWithPCVController() public {
        uint256 depositBalance = 10_000_000e18;
        uint256 startingTime = dripper.startTime();

        token.mint(address(erc20HoldingDepositPull), depositBalance);
        vm.warp(block.timestamp + frequency);
        dripper.drip();

        assertEq(startingTime + frequency, dripper.startTime()); /// ensure start time updates correctly
        assertEq(
            token.balanceOf(address(erc20HoldingDepositPull)),
            depositBalance - dripThreshold
        );
        assertEq(
            token.balanceOf(address(erc20HoldingDepositPush)),
            dripThreshold
        );
    }

    function testPullSucceedsWhenOverThresholdWithPCVControllerFuzz(
        uint128 depositBalance
    ) public {
        token.mint(address(erc20HoldingDepositPull), depositBalance);
        vm.warp(block.timestamp + dripper.duration());

        if (depositBalance >= dripThreshold) {
            uint256 startingTime = dripper.startTime();
            vm.expectEmit(true, false, false, true, address(dripper));
            emit Dripped(dripThreshold);
            dripper.drip();

            assertEq(startingTime + frequency, dripper.startTime()); /// ensure start time updates correctly
            assertEq(
                token.balanceOf(address(erc20HoldingDepositPull)),
                depositBalance - dripThreshold
            );
            assertEq(
                token.balanceOf(address(erc20HoldingDepositPush)),
                dripThreshold
            );
        } else {
            vm.expectEmit(true, false, false, true, address(dripper));
            emit Dripped(0);
            dripper.drip();
        }
    }
}
