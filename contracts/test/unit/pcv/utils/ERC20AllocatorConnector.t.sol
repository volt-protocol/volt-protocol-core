pragma solidity =0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "./../../utils/Vm.sol";
import {ICore} from "../../../../core/ICore.sol";
import {DSTest} from "./../../utils/DSTest.sol";
import {MockPSM} from "../../../../mock/MockPSM.sol";
import {MockERC20} from "../../../../mock/MockERC20.sol";
import {PCVDeposit} from "../../../../pcv/PCVDeposit.sol";
import {VoltRoles} from "../../../../core/VoltRoles.sol";
import {PCVGuardAdmin} from "../../../../pcv/PCVGuardAdmin.sol";
import {ERC20Allocator} from "../../../../pcv/utils/ERC20Allocator.sol";
import {ERC20HoldingPCVDeposit} from "../../../../pcv/ERC20HoldingPCVDeposit.sol";
import {getCore, getAddresses, VoltTestAddresses} from "./../../utils/Fixtures.sol";

import "hardhat/console.sol";

contract UnitTestERC20AllocatorConnector is DSTest {
    /// @notice emitted when an existing deposit is updated
    event DepositUpdated(
        address psm,
        address pcvDeposit,
        address token,
        uint248 targetBalance,
        int8 decimalsNormalizer
    );

    /// @notice PSM deletion event
    event PSMDeleted(address psm);

    /// @notice event emitted when tokens are dripped
    event Dripped(uint256 amount);

    /// @notice event emitted in do action when neither skim nor drip could be triggered
    event NoOp();

    /// @notice emitted when an existing deposit is deleted
    event DepositDeleted(address psm);

    /// @notice emitted when a psm is connected to a PCV Deposit
    event DepositConnected(address psm, address pcvDeposit);

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

    function testSkimFailsToNonConnectedAddress(address deposit) public {
        vm.assume(deposit != address(pcvDeposit));
        vm.expectRevert("ERC20Allocator: invalid PCVDeposit");
        allocator.skim(address(deposit));
    }

    function testDripFailsToNonConnectedAddress(address deposit) public {
        vm.assume(deposit != address(pcvDeposit));
        vm.expectRevert("ERC20Allocator: invalid PCVDeposit");
        allocator.drip(address(deposit));
    }

    function testConnectNewDepositSkimToDripFrom() public {
        PCVDeposit newPcvDeposit = new ERC20HoldingPCVDeposit(
            address(core),
            IERC20(address(token)),
            address(0)
        );

        vm.startPrank(addresses.governorAddress);
        allocator.connectDeposit(address(psm), address(newPcvDeposit));
        core.grantPCVController(address(allocator));
        vm.stopPrank();

        assertEq(
            address(psm),
            allocator.pcvDepositToPSM(address(newPcvDeposit))
        );
        assertEq(psm.balance(), 0);

        /// drip
        token.mint(address(newPcvDeposit), targetBalance);
        allocator.drip(address(newPcvDeposit));

        assertEq(psm.balance(), targetBalance);
        assertEq(newPcvDeposit.balance(), 0);

        /// skim
        token.mint(address(psm), targetBalance);

        assertEq(psm.balance(), targetBalance * 2);

        allocator.skim(address(newPcvDeposit));

        assertEq(psm.balance(), targetBalance);
        assertEq(newPcvDeposit.balance(), targetBalance);
    }

    function testConnectNewDepositFailsTokenMismatch() public {
        PCVDeposit newPcvDeposit = new ERC20HoldingPCVDeposit(
            address(core),
            IERC20(address(0)),
            address(0)
        );

        vm.prank(addresses.governorAddress);
        vm.expectRevert("ERC20Allocator: token mismatch");
        allocator.connectDeposit(address(psm), address(newPcvDeposit));
    }

    function testConnectAndRemoveNewDeposit() public {
        PCVDeposit newPcvDeposit = new ERC20HoldingPCVDeposit(
            address(core),
            IERC20(address(token)),
            address(0)
        );

        vm.prank(addresses.governorAddress);
        allocator.connectDeposit(address(psm), address(newPcvDeposit));

        assertEq(
            allocator.pcvDepositToPSM(address(newPcvDeposit)),
            address(psm)
        );

        vm.prank(addresses.governorAddress);
        allocator.deleteDeposit(address(newPcvDeposit));

        assertEq(allocator.pcvDepositToPSM(address(newPcvDeposit)), address(0));

        vm.expectRevert("ERC20Allocator: invalid PCVDeposit");
        allocator.drip(address(newPcvDeposit));

        vm.expectRevert("ERC20Allocator: invalid PCVDeposit");
        allocator.skim(address(newPcvDeposit));
    }

    function testCreateNewDepositFailsUnderlyingTokenMismatch() public {
        PCVDeposit newPcvDeposit = new ERC20HoldingPCVDeposit(
            address(core),
            IERC20(address(1)),
            address(0)
        );

        ERC20HoldingPCVDeposit newPsm = new ERC20HoldingPCVDeposit(
            address(core),
            IERC20(address(token)),
            address(0)
        );

        vm.startPrank(addresses.governorAddress);
        allocator.connectPSM(address(newPsm), 0, 0);
        vm.expectRevert("ERC20Allocator: token mismatch");
        allocator.connectDeposit(address(newPsm), address(newPcvDeposit));
        vm.stopPrank();
    }

    function testConnectNewDepositFailsUnderlyingTokenMismatch() public {
        PCVDeposit newPcvDeposit = new ERC20HoldingPCVDeposit(
            address(core),
            IERC20(address(1)),
            address(0)
        );

        vm.expectRevert("ERC20Allocator: token mismatch");
        vm.prank(addresses.governorAddress);
        allocator.connectDeposit(address(psm), address(newPcvDeposit));
    }

    function testEditPSMTargetBalanceFailsPsmUnderlyingChanged() public {
        MockPSM newPsm = new MockPSM(address(token));
        vm.prank(addresses.governorAddress);
        allocator.connectPSM(address(newPsm), targetBalance, 0);
        newPsm.setUnderlying(address(1));

        vm.expectRevert("ERC20Allocator: psm changed underlying");
        vm.prank(addresses.governorAddress);
        allocator.editPSMTargetBalance(address(newPsm), 0);
    }

    function testCreateDuplicateDepositFails() public {
        vm.expectRevert("ERC20Allocator: cannot overwrite existing deposit");
        vm.prank(addresses.governorAddress);
        allocator.connectPSM(address(psm), targetBalance, 0);
    }

    function testSetTargetBalanceNonExistingPsmFails() public {
        MockPSM newPsm = new MockPSM(address(token));
        vm.expectRevert("ERC20Allocator: cannot edit non-existent deposit");
        vm.prank(addresses.governorAddress);
        allocator.editPSMTargetBalance(address(newPsm), targetBalance);
    }
}
