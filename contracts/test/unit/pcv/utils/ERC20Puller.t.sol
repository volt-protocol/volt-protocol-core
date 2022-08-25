pragma solidity =0.8.13;

import {Vm} from "./../../utils/Vm.sol";
import {ICore} from "../../../../core/ICore.sol";
import {DSTest} from "./../../utils/DSTest.sol";
import {MockERC20} from "../../../../mock/MockERC20.sol";
import {TribeRoles} from "../../../../core/TribeRoles.sol";
import {ERC20Puller} from "../../../../pcv/utils/ERC20Puller.sol";
import {PCVGuardAdmin} from "../../../../pcv/PCVGuardAdmin.sol";
import {ERC20HoldingPCVDeposit} from "../../../../pcv/ERC20HoldingPCVDeposit.sol";
import {getCore, getAddresses, VoltTestAddresses} from "./../../utils/Fixtures.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UnitTestERC20Puller is DSTest {
    event PullThresholdUpdate(uint256 oldThreshold, uint256 newThreshold);

    ICore private core;
    Vm public constant vm = Vm(HEVM_ADDRESS);
    VoltTestAddresses public addresses = getAddresses();

    /// @notice reference to the PCVDeposit to pull from
    ERC20HoldingPCVDeposit private erc20HoldingDepositPull;

    /// @notice reference to the PCVDeposit to push to
    ERC20HoldingPCVDeposit private erc20HoldingDepositPush;

    /// @notice reference to the ERC20
    ERC20Puller private erc20Puller;

    /// @notice token to push
    MockERC20 private token;

    /// @notice threshold over which to pull tokens from pull deposit
    uint256 private constant pullThreshold = 100_000e18;

    function setUp() public {
        core = getCore();
        token = new MockERC20();

        erc20HoldingDepositPull = new ERC20HoldingPCVDeposit(
            address(core),
            IERC20(address(token))
        );

        erc20HoldingDepositPush = new ERC20HoldingPCVDeposit(
            address(core),
            IERC20(address(token))
        );

        erc20Puller = new ERC20Puller(
            address(core),
            address(erc20HoldingDepositPush),
            address(erc20HoldingDepositPull),
            pullThreshold,
            address(token)
        );
    }

    function testPullFailsWhenUnderFunded() public {
        vm.expectRevert("ERC20Puller: condition not met");
        erc20Puller.pull();
    }

    function testSetPullThresholdNonGovFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        erc20Puller.setPullThreshold(0);
    }

    function testPullFailsWhenPaused() public {
        vm.prank(addresses.governorAddress);
        erc20Puller.pause();

        vm.expectRevert("Pausable: paused");
        erc20Puller.pull();
    }

    function testPullFailsWhenOverThresholdWithoutPCVController() public {
        uint256 depositBalance = 10_000_000e18;

        token.mint(address(erc20HoldingDepositPull), depositBalance);

        vm.expectRevert("UNAUTHORIZED");
        erc20Puller.pull();
    }

    function testSetPullThresholdGovSucceeds() public {
        uint256 newThreshold = 10_000_000e18;

        vm.startPrank(addresses.governorAddress);
        vm.expectEmit(true, false, false, true, address(erc20Puller));
        emit PullThresholdUpdate(pullThreshold, newThreshold);
        erc20Puller.setPullThreshold(newThreshold);
        vm.stopPrank();

        assertEq(newThreshold, erc20Puller.pullThreshold());
    }

    function testPullSucceedsWhenOverThresholdWithPCVController() public {
        uint256 depositBalance = 10_000_000e18;

        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(erc20Puller));

        token.mint(address(erc20HoldingDepositPull), depositBalance);
        erc20Puller.pull();

        assertEq(
            token.balanceOf(address(erc20HoldingDepositPull)),
            pullThreshold
        );
        assertEq(
            token.balanceOf(address(erc20HoldingDepositPush)),
            depositBalance - pullThreshold
        );
    }

    function testPullSucceedsWhenOverThresholdWithPCVControllerFuzz(
        uint128 depositBalance
    ) public {
        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(erc20Puller));
        token.mint(address(erc20HoldingDepositPull), depositBalance);

        if (depositBalance > pullThreshold) {
            erc20Puller.pull();

            assertEq(
                token.balanceOf(address(erc20HoldingDepositPull)),
                pullThreshold
            );
            assertEq(
                token.balanceOf(address(erc20HoldingDepositPush)),
                depositBalance - pullThreshold
            );
        } else {
            vm.expectRevert("ERC20Puller: condition not met");
            erc20Puller.pull();
        }
    }
}
