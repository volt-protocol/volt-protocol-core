pragma solidity =0.8.13;

import {Vm} from "./../../utils/Vm.sol";
import {ICore} from "../../../../core/ICore.sol";
import {DSTest} from "./../../utils/DSTest.sol";
import {MockERC20} from "../../../../mock/MockERC20.sol";
import {ERC20Skimmer} from "../../../../pcv/utils/ERC20Skimmer.sol";
import {ERC20HoldingPCVDeposit} from "../../../../pcv/ERC20HoldingPCVDeposit.sol";
import {getCore, getAddresses, VoltTestAddresses} from "./../../utils/Fixtures.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "hardhat/console.sol";

contract UnitTestERC20Skimmer is DSTest {
    ICore private core;
    Vm public constant vm = Vm(HEVM_ADDRESS);
    VoltTestAddresses public addresses = getAddresses();

    /// @notice reference to the PCVDeposit to pull from
    ERC20HoldingPCVDeposit private pcvDeposit0;

    /// @notice reference to the PCVDeposit to pull from
    ERC20HoldingPCVDeposit private pcvDeposit1;

    /// @notice reference to the PCVDeposit that cannot be pulled from
    ERC20HoldingPCVDeposit private pcvDeposit2;

    /// @notice reference to the ERC20
    ERC20Skimmer private skimmer;

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

    /// @notice target address where funds will be sent
    address target = address(100_000_000);

    function setUp() public {
        core = getCore();
        token = new MockERC20();

        pcvDeposit0 = new ERC20HoldingPCVDeposit(
            address(core),
            IERC20(address(token)),
            address(0)
        );

        pcvDeposit1 = new ERC20HoldingPCVDeposit(
            address(core),
            IERC20(address(token)),
            address(0)
        );

        pcvDeposit2 = new ERC20HoldingPCVDeposit(
            address(core),
            IERC20(address(token)),
            address(0)
        );

        skimmer = new ERC20Skimmer(address(core), target, address(token));

        vm.startPrank(addresses.governorAddress);

        skimmer.addDeposit(address(pcvDeposit0));
        skimmer.addDeposit(address(pcvDeposit1));
        core.grantPCVController(address(skimmer));

        vm.stopPrank();
    }

    function testSetup() public {
        assertTrue(skimmer.isDepositWhitelisted(address(pcvDeposit0)));
        assertTrue(skimmer.isDepositWhitelisted(address(pcvDeposit1)));
        assertTrue(core.isPCVController(address(skimmer)));
        assertEq(skimmer.target(), target);
        assertEq(skimmer.token(), address(token));
    }

    function testSkimFromDeposit0Succeeds(uint128 mintAmount) public {
        assertEq(token.balanceOf(address(target)), 0);

        token.mint(address(pcvDeposit0), mintAmount);
        skimmer.skim(address(pcvDeposit0));

        assertEq(token.balanceOf(address(target)), mintAmount);
    }

    function testSkimFromDeposit0FailsSkimmerNotPCVController() public {
        vm.prank(addresses.governorAddress);
        core.revokePCVController(address(skimmer));

        assertTrue(!core.isPCVController(address(skimmer)));

        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        skimmer.skim(address(pcvDeposit0));
    }

    function testSkimFromDeposit1Succeeds(uint128 mintAmount) public {
        assertEq(token.balanceOf(address(target)), 0);

        token.mint(address(pcvDeposit1), mintAmount);
        skimmer.skim(address(pcvDeposit1));

        assertEq(token.balanceOf(address(target)), mintAmount);
    }

    function testSkimFailsFromDepositNotInList() public {
        vm.expectRevert("ERC20Skimmer: invalid target");
        skimmer.skim(address(pcvDeposit2));
    }

    function testSkimFailsFromDepositNotInListFuzz(address targetDeposit)
        public
    {
        if (skimmer.isDepositWhitelisted(targetDeposit)) {
            skimmer.skim(targetDeposit);
        } else {
            vm.expectRevert("ERC20Skimmer: invalid target");
            skimmer.skim(address(pcvDeposit2));
        }
    }

    function testNonGovAddDepositFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        skimmer.addDeposit(address(pcvDeposit2));
    }

    function testNonGovRemoveDepositFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        skimmer.removeDeposit(address(pcvDeposit2));
    }

    function testGovAddDuplicateDepositFails() public {
        vm.prank(addresses.governorAddress);
        vm.expectRevert("ERC20Skimmer: already in list");
        skimmer.addDeposit(address(pcvDeposit1));
    }

    function testGovRemoveNonExistentDepositFails() public {
        vm.prank(addresses.governorAddress);
        vm.expectRevert("ERC20Skimmer: not in list");
        skimmer.removeDeposit(address(pcvDeposit2));
    }

    function testGovRemoveDepositSucceeds() public {
        vm.prank(addresses.governorAddress);
        skimmer.removeDeposit(address(pcvDeposit1));
        assertTrue(!skimmer.isDepositWhitelisted(address(pcvDeposit1)));
    }

    function testGovAddDepositSucceeds() public {
        vm.prank(addresses.governorAddress);
        skimmer.addDeposit(address(pcvDeposit2));
        assertTrue(skimmer.isDepositWhitelisted(address(pcvDeposit2)));
    }
}
