pragma solidity ^0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {Vm} from "../../../unit/utils/Vm.sol";
import {DSTest} from "../../../unit/utils/DSTest.sol";
import {ERC20Allocator} from "../../../../pcv/utils/ERC20Allocator.sol";
import {CompoundPCVRouter} from "../../../../pcv/compound/CompoundPCVRouter.sol";
import {CompoundPCVDepositV2} from "../../../../pcv/compound/CompoundPCVDepositV2.sol";
import {Core} from "../../../../core/Core.sol";
import {TribeRoles} from "../../../../core/TribeRoles.sol";
import {MockERC20} from "../../../../mock/MockERC20.sol";
import {MainnetAddresses} from "../../fixtures/MainnetAddresses.sol";
import {ArbitrumAddresses} from "../../fixtures/ArbitrumAddresses.sol";
import {PriceBoundPSM} from "../../../../peg/PriceBoundPSM.sol";

contract CompoundPCVSetupIntegrationTest is DSTest {
    // using SafeCast for *;
    // Vm public constant vm = Vm(HEVM_ADDRESS);
    // Core private core = Core(MainnetAddresses.CORE);
    // IERC20 private usdc = IERC20(MainnetAddresses.USDC);
    // IERC20 private dai = IERC20(MainnetAddresses.DAI);
    // address private governor = MainnetAddresses.GOVERNOR;
    // CompoundPCVRouter private compoundRouter;
    // CompoundPCVDepositV2 private daiDeposit;
    // CompoundPCVDepositV2 private usdcDeposit;
    // ERC20Allocator private daiAllocator;
    // ERC20Allocator private usdcAllocator;
    // PriceBoundPSM private constant usdcPsm =
    //     PriceBoundPSM(MainnetAddresses.VOLT_USDC_PSM);
    // PriceBoundPSM private constant daiPsm =
    //     PriceBoundPSM(MainnetAddresses.VOLT_DAI_PSM);
    // uint256 public constant depositAmount = 10_000_000e18;
    // uint256 public constant target = 100_000e18;
    // address public constant compoundPCVMover = address(1);
    // uint256 public constant MAX_RATE_LIMIT_PER_SECOND_DAI = 100_000e18;
    // uint256 public constant MAX_RATE_LIMIT_PER_SECOND_USDC = 100_000e18;
    // uint256 public constant rateLimitPerSecond = 10_000e18;
    // uint256 public constant bufferCap = 10_000_000e18;
    // /// @notice scaling factor for USDC
    // uint256 public constant USDC_SCALING_FACTOR = 1e12;
    // function setUp() public {
    //     daiDeposit = new CompoundPCVDepositV2(
    //         address(core),
    //         MainnetAddresses.CDAI
    //     );
    //     usdcDeposit = new CompoundPCVDepositV2(
    //         address(core),
    //         MainnetAddresses.CUSDC
    //     );
    //     compoundRouter = new CompoundPCVRouter(
    //         address(core),
    //         MainnetAddresses.MAKER_DAI_USDC_PSM,
    //         daiDeposit,
    //         usdcDeposit
    //     );
    //     daiAllocator = new ERC20Allocator(
    //         address(core),
    //         address(daiDeposit),
    //         address(daiPsm),
    //         target,
    //         MAX_RATE_LIMIT_PER_SECOND_DAI,
    //         rateLimitPerSecond,
    //         bufferCap
    //     );
    //     usdcAllocator = new ERC20Allocator(
    //         address(core),
    //         address(usdcDeposit),
    //         address(usdcPsm),
    //         target / 1e12,
    //         MAX_RATE_LIMIT_PER_SECOND_USDC,
    //         rateLimitPerSecond / USDC_SCALING_FACTOR,
    //         bufferCap / USDC_SCALING_FACTOR
    //     );
    //     /// role setup
    //     vm.startPrank(governor);
    //     core.grantPCVController(address(compoundRouter));
    //     core.createRole(TribeRoles.COMPOUND_PCV_MOVER, TribeRoles.GOVERNOR);
    //     core.grantRole(TribeRoles.COMPOUND_PCV_MOVER, compoundPCVMover);
    //     vm.stopPrank();
    //     /// get funding for PCV Deposits
    //     vm.startPrank(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
    //     dai.transfer(address(daiDeposit), depositAmount);
    //     usdc.transfer(
    //         address(usdcDeposit),
    //         depositAmount / USDC_SCALING_FACTOR
    //     );
    //     vm.stopPrank();
    //     daiDeposit.deposit();
    //     usdcDeposit.deposit();
    // }
    // function testSetup() public {
    //     /// cToken share price rounds down against depositors,
    //     /// this means balance is a hair under deposit amount
    //     assertApproxEq(
    //         daiDeposit.balance().toInt256(),
    //         depositAmount.toInt256(),
    //         0
    //     );
    //     assertApproxEq(
    //         usdcDeposit.balance().toInt256(),
    //         (depositAmount / USDC_SCALING_FACTOR).toInt256(),
    //         0
    //     );
    //     assertTrue(
    //         core.hasRole(TribeRoles.COMPOUND_PCV_MOVER, compoundPCVMover)
    //     );
    //     assertTrue(core.isPCVController(address(compoundRouter)));
    //     assertEq(
    //         address(compoundRouter.daiPSM()),
    //         MainnetAddresses.MAKER_DAI_USDC_PSM
    //     );
    //     assertEq(address(compoundRouter.daiPcvDeposit()), address(daiDeposit));
    //     assertEq(
    //         address(compoundRouter.usdcPcvDeposit()),
    //         address(usdcDeposit)
    //     );
    //     /// allocators
    //     assertEq(daiAllocator.token(), MainnetAddresses.DAI);
    //     assertEq(usdcAllocator.token(),MainnetAddresses.USDC);
    //     assertEq(daiAllocator.psm(), address(daiPsm));
    //     assertEq(usdcAllocator.psm(), address(usdcPsm));
    //     assertEq(daiAllocator.pcvDeposit(), address(daiDeposit));
    //     assertEq(usdcAllocator.pcvDeposit(), address(usdcDeposit));
    //     assertEq(daiAllocator.targetBalance(), target);
    //     assertEq(usdcAllocator.targetBalance(), target / USDC_SCALING_FACTOR);
    //     assertEq(daiAllocator.targetBalance(), target);
    //     assertEq(usdcAllocator.targetBalance(), target / USDC_SCALING_FACTOR);
    //     assertEq(daiAllocator.targetBalance(), target);
    //     assertEq(usdcAllocator.targetBalance(), target / USDC_SCALING_FACTOR);
    // }
    // function testSwapDaiToUsdcSucceeds() public {
    //     uint256 withdrawAmount = daiDeposit.balance();
    //     vm.prank(governor);
    //     compoundRouter.swapDaiForUsdc(withdrawAmount); /// withdraw all balance
    //     assertApproxEq(
    //         usdcDeposit.balance().toInt256(),
    //         ((withdrawAmount * 2) / USDC_SCALING_FACTOR).toInt256(),
    //         0
    //     );
    //     assertTrue(daiDeposit.balance() < 1e9); /// assert only dust remains
    // }
    // function testSwapUsdcToDaiSucceeds() public {
    //     uint256 withdrawAmount = usdcDeposit.balance();
    //     vm.prank(governor);
    //     compoundRouter.swapUsdcForDai(withdrawAmount); /// withdraw all balance
    //     assertApproxEq(
    //         daiDeposit.balance().toInt256(),
    //         (depositAmount * 2).toInt256(),
    //         0
    //     );
    //     assertTrue(usdcDeposit.balance() < 1e3); /// assert only dust remains
    // }
    // function testSwapUsdcToDaiSucceedsCompPCVMover() public {
    //     vm.prank(compoundPCVMover);
    // }
    // function testSwapDaiToUsdcSucceedsCompPCVMover() public {
    //     vm.prank(compoundPCVMover);
    // }
    // function testSwapUsdcToDaiFailsNoLiquidity() public {}
    // function testSwapDaiToUsdcFailsNoLiquidity() public {}
    // function testSwapUsdcToDaiFailsUnauthorized() public {}
    // function testSwapDaiToUsdcFailsUnauthorized() public {}
}
