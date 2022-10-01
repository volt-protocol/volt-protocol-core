pragma solidity =0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "./../unit/utils/Vm.sol";
import {ICore} from "../../core/ICore.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {vip14} from "./vip/vip14.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {IPCVGuardian} from "../../pcv/IPCVGuardian.sol";
import {ERC20Skimmer} from "../../pcv/utils/ERC20Skimmer.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {TimelockSimulation} from "./utils/TimelockSimulation.sol";
import {ERC20CompoundPCVDeposit} from "../../pcv/compound/ERC20CompoundPCVDeposit.sol";

contract IntegrationTestERC20Skimmer is vip14, TimelockSimulation {
    ICore private core = ICore(MainnetAddresses.CORE);

    /// @notice reference to the dai compound PCVDeposit to pull from
    ERC20CompoundPCVDeposit private daiDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_DAI_PCV_DEPOSIT);

    /// @notice reference to the usdc compound PCVDeposit to pull from
    ERC20CompoundPCVDeposit private usdcDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT);

    /// @notice token to push
    IERC20 private comp = IERC20(MainnetAddresses.COMP);

    /// @notice pcv guardian on mainnet
    IPCVGuardian private mainnetPCVGuardian =
        IPCVGuardian(MainnetAddresses.PCV_GUARDIAN);

    /// @notice threshold over which to pull tokens from pull deposit
    uint248 private constant targetBalance = 100_000e18;

    /// @notice maximum rate limit per second in RateLimitedV2
    uint256 private constant maxRateLimitPerSecond = 1_000_000e18;

    /// @notice rate limit per second in RateLimitedV2
    uint128 private constant rateLimitPerSecond = 10_000e18;

    /// @notice buffer cap in RateLimitedV2
    uint128 private constant bufferCap = 10_000_000e18;

    /// @notice target address where funds will be sent,
    /// comp PSM
    address target;

    function setUp() public {
        target = address(compPSM);
        mainnetSetup();
        simulate(
            getMainnetProposal(),
            TimelockController(payable(MainnetAddresses.TIMELOCK_CONTROLLER)),
            mainnetPCVGuardian,
            MainnetAddresses.GOVERNOR,
            MainnetAddresses.EOA_1,
            vm,
            false
        );
        mainnetValidate();
    }

    function testSetup() public {
        assertEq(address(erc20Skimmer.core()), address(core));

        assertTrue(erc20Skimmer.isDepositWhitelisted(address(daiDeposit)));
        assertTrue(erc20Skimmer.isDepositWhitelisted(address(usdcDeposit)));

        assertTrue(core.isPCVController(address(erc20Skimmer)));
        assertEq(erc20Skimmer.target(), target);
        assertEq(erc20Skimmer.token(), address(comp));
    }

    function testSkimFromDeposit0Succeeds() public {
        uint256 startingTokenBalance = comp.balanceOf(address(daiDeposit));

        erc20Skimmer.skim(address(daiDeposit));

        assertEq(comp.balanceOf(address(daiDeposit)), 0);
        assertEq(comp.balanceOf(address(target)), startingTokenBalance);
    }

    function testSkimFromDeposit1Succeeds() public {
        uint256 startingTokenBalance = comp.balanceOf(address(usdcDeposit));

        erc20Skimmer.skim(address(usdcDeposit));

        assertEq(comp.balanceOf(address(usdcDeposit)), 0);
        assertEq(comp.balanceOf(address(target)), startingTokenBalance);
    }

    function testSkimFromDeposit0Failserc20SkimmerNotPCVController() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        core.revokePCVController(address(erc20Skimmer));

        assertTrue(!core.isPCVController(address(erc20Skimmer)));

        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        erc20Skimmer.skim(address(daiDeposit));
    }

    function testSkimFailsFromDepositNotInList() public {
        vm.expectRevert("ERC20Skimmer: invalid target");
        erc20Skimmer.skim(address(erc20Skimmer));
    }

    function testSkimFailsFromDepositNotInListFuzz(address targetDeposit)
        public
    {
        if (erc20Skimmer.isDepositWhitelisted(targetDeposit)) {
            uint256 startingTokenBalance = comp.balanceOf(targetDeposit);

            erc20Skimmer.skim(targetDeposit);

            assertEq(comp.balanceOf(targetDeposit), 0);
            assertEq(comp.balanceOf(target), startingTokenBalance);
        } else {
            vm.expectRevert("ERC20Skimmer: invalid target");
            erc20Skimmer.skim(targetDeposit);
        }
    }

    function testNonGovAddDepositFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        erc20Skimmer.addDeposit(address(1010199110));
    }

    function testNonGovRemoveDepositFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        erc20Skimmer.removeDeposit(address(1010199110));
    }

    function testGovAddDuplicateDepositFails() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        vm.expectRevert("ERC20Skimmer: already in list");
        erc20Skimmer.addDeposit(address(daiDeposit));
    }

    function testGovRemoveNonExistentDepositFails() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        vm.expectRevert("ERC20Skimmer: not in list");
        erc20Skimmer.removeDeposit(address(1010199110));
    }

    function testGovRemoveDepositSucceeds() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        erc20Skimmer.removeDeposit(address(daiDeposit));
        assertTrue(!erc20Skimmer.isDepositWhitelisted(address(daiDeposit)));
    }

    function testGovAddDepositSucceeds() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        erc20Skimmer.addDeposit(address(1010199110));
        assertTrue(erc20Skimmer.isDepositWhitelisted(address(1010199110)));
    }
}
