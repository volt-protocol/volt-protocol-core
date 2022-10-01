pragma solidity =0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "./../unit/utils/Vm.sol";
import {ICore} from "../../core/ICore.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {ERC20Skimmer} from "../../pcv/utils/ERC20Skimmer.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {ERC20HoldingPCVDeposit} from "../../pcv/ERC20HoldingPCVDeposit.sol";
import {ERC20CompoundPCVDeposit} from "../../pcv/compound/ERC20CompoundPCVDeposit.sol";

contract IntegrationTestERC20Skimmer is DSTest {
    ICore private core = ICore(MainnetAddresses.CORE);
    Vm public constant vm = Vm(HEVM_ADDRESS);

    /// @notice reference to the dai compound PCVDeposit to pull from
    ERC20CompoundPCVDeposit private daiDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_DAI_PCV_DEPOSIT);

    /// @notice reference to the usdc compound PCVDeposit to pull from
    ERC20CompoundPCVDeposit private usdcDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT);

    /// @notice reference to the ERC20
    ERC20Skimmer private skimmer;

    /// @notice token to push
    IERC20 private comp = IERC20(MainnetAddresses.COMP);

    /// @notice threshold over which to pull tokens from pull deposit
    uint248 private constant targetBalance = 100_000e18;

    /// @notice maximum rate limit per second in RateLimitedV2
    uint256 private constant maxRateLimitPerSecond = 1_000_000e18;

    /// @notice rate limit per second in RateLimitedV2
    uint128 private constant rateLimitPerSecond = 10_000e18;

    /// @notice buffer cap in RateLimitedV2
    uint128 private constant bufferCap = 10_000_000e18;

    /// @notice target address where funds will be sent
    address target = MainnetAddresses.GOVERNOR;

    function setUp() public {
        skimmer = new ERC20Skimmer(address(core), target, address(comp));

        vm.startPrank(MainnetAddresses.GOVERNOR);

        skimmer.addDeposit(address(daiDeposit));
        skimmer.addDeposit(address(usdcDeposit));
        core.grantPCVController(address(skimmer));

        vm.stopPrank();
    }

    function testSetup() public {
        assertEq(address(skimmer.core()), address(core));

        assertTrue(skimmer.isDepositWhitelisted(address(daiDeposit)));
        assertTrue(skimmer.isDepositWhitelisted(address(usdcDeposit)));

        assertTrue(core.isPCVController(address(skimmer)));
        assertEq(skimmer.target(), target);
        assertEq(skimmer.token(), address(comp));
    }

    function testSkimFromDeposit0Succeeds() public {
        uint256 startingTokenBalance = comp.balanceOf(address(daiDeposit));

        skimmer.skim(address(daiDeposit));

        assertEq(comp.balanceOf(address(daiDeposit)), 0);
        assertEq(comp.balanceOf(address(target)), startingTokenBalance);
    }

    function testSkimFromDeposit1Succeeds() public {
        uint256 startingTokenBalance = comp.balanceOf(address(usdcDeposit));

        skimmer.skim(address(usdcDeposit));

        assertEq(comp.balanceOf(address(usdcDeposit)), 0);
        assertEq(comp.balanceOf(address(target)), startingTokenBalance);
    }

    function testSkimFromDeposit0FailsSkimmerNotPCVController() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        core.revokePCVController(address(skimmer));

        assertTrue(!core.isPCVController(address(skimmer)));

        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        skimmer.skim(address(daiDeposit));
    }

    function testSkimFailsFromDepositNotInList() public {
        vm.expectRevert("ERC20Skimmer: invalid target");
        skimmer.skim(address(skimmer));
    }

    function testSkimFailsFromDepositNotInListFuzz(address targetDeposit)
        public
    {
        if (skimmer.isDepositWhitelisted(targetDeposit)) {
            uint256 startingTokenBalance = comp.balanceOf(targetDeposit);

            skimmer.skim(targetDeposit);

            assertEq(comp.balanceOf(targetDeposit), 0);
            assertEq(comp.balanceOf(target), startingTokenBalance);
        } else {
            vm.expectRevert("ERC20Skimmer: invalid target");
            skimmer.skim(targetDeposit);
        }
    }

    function testNonGovAddDepositFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        skimmer.addDeposit(address(1010199110));
    }

    function testNonGovRemoveDepositFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        skimmer.removeDeposit(address(1010199110));
    }

    function testGovAddDuplicateDepositFails() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        vm.expectRevert("ERC20Skimmer: already in list");
        skimmer.addDeposit(address(daiDeposit));
    }

    function testGovRemoveNonExistentDepositFails() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        vm.expectRevert("ERC20Skimmer: not in list");
        skimmer.removeDeposit(address(1010199110));
    }

    function testGovRemoveDepositSucceeds() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        skimmer.removeDeposit(address(daiDeposit));
        assertTrue(!skimmer.isDepositWhitelisted(address(daiDeposit)));
    }

    function testGovAddDepositSucceeds() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        skimmer.addDeposit(address(1010199110));
        assertTrue(skimmer.isDepositWhitelisted(address(1010199110)));
    }
}
