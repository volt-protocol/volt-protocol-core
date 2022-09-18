pragma solidity ^0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {Vm} from "../../unit/utils/Vm.sol";
import {DSTest} from "../../unit/utils/DSTest.sol";
import {CompoundPCVRouter} from "../../../pcv/compound/CompoundPCVRouter.sol";
import {ERC20CompoundPCVDeposit} from "../../../pcv/compound/ERC20CompoundPCVDeposit.sol";
import {Core} from "../../../core/Core.sol";
import {TribeRoles} from "../../../core/TribeRoles.sol";
import {MockERC20} from "../../../mock/MockERC20.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {ArbitrumAddresses} from "../fixtures/ArbitrumAddresses.sol";

contract CompoundPCVRouterIntegrationTest is DSTest {
    using SafeCast for *;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    Core private core = Core(MainnetAddresses.CORE);
    IERC20 private usdc = IERC20(MainnetAddresses.USDC);
    IERC20 private dai = IERC20(MainnetAddresses.DAI);
    address private governor = MainnetAddresses.GOVERNOR;

    CompoundPCVRouter private compoundRouter;
    ERC20CompoundPCVDeposit private daiDeposit;
    ERC20CompoundPCVDeposit private usdcDeposit;

    uint256 public constant depositAmount = 10_000_000e18;
    address public constant compoundPCVMover = address(1);

    /// @notice scaling factor for USDC
    uint256 public constant USDC_SCALING_FACTOR = 1e12;

    function setUp() public {
        daiDeposit = new ERC20CompoundPCVDeposit(
            address(core),
            MainnetAddresses.CDAI
        );

        usdcDeposit = new ERC20CompoundPCVDeposit(
            address(core),
            MainnetAddresses.CUSDC
        );

        compoundRouter = new CompoundPCVRouter(
            address(core),
            MainnetAddresses.MAKER_DAI_USDC_PSM,
            daiDeposit,
            usdcDeposit
        );

        /// role setup
        vm.prank(governor);
        core.grantPCVController(address(compoundRouter));

        /// get funding for PCV Deposits
        vm.startPrank(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        dai.transfer(address(daiDeposit), depositAmount);
        usdc.transfer(
            address(usdcDeposit),
            depositAmount / USDC_SCALING_FACTOR
        );
        vm.stopPrank();

        daiDeposit.deposit();
        usdcDeposit.deposit();
    }

    function testSetup() public {
        /// cToken share price rounds down against depositors,
        /// this means balance is a hair under deposit amount
        assertApproxEq(
            daiDeposit.balance().toInt256(),
            depositAmount.toInt256(),
            0
        );
        assertApproxEq(
            usdcDeposit.balance().toInt256(),
            (depositAmount / USDC_SCALING_FACTOR).toInt256(),
            0
        );

        assertTrue(core.isPCVController(address(compoundRouter)));

        assertEq(
            address(compoundRouter.daiPSM()),
            MainnetAddresses.MAKER_DAI_USDC_PSM
        );
        assertEq(address(compoundRouter.daiPcvDeposit()), address(daiDeposit));
        assertEq(
            address(compoundRouter.usdcPcvDeposit()),
            address(usdcDeposit)
        );
    }

    function testSwapDaiToUsdcSucceeds() public {
        uint256 withdrawAmount = daiDeposit.balance();

        vm.prank(governor);
        compoundRouter.swapDaiForUsdc(withdrawAmount); /// withdraw all balance

        assertApproxEq(
            usdcDeposit.balance().toInt256(),
            ((withdrawAmount * 2) / USDC_SCALING_FACTOR).toInt256(),
            0
        );
        assertTrue(daiDeposit.balance() < 1e9); /// assert only dust remains
    }

    function testSwapUsdcToDaiSucceeds() public {
        uint256 withdrawAmount = usdcDeposit.balance();

        vm.prank(governor);
        compoundRouter.swapUsdcForDai(withdrawAmount); /// withdraw all balance

        assertApproxEq(
            daiDeposit.balance().toInt256(),
            (depositAmount * 2).toInt256(),
            0
        );
        assertTrue(usdcDeposit.balance() < 1e3); /// assert only dust remains
    }

    function testSwapUsdcToDaiSucceedsCompPCVMover() public {
        vm.prank(compoundPCVMover);
    }

    function testSwapDaiToUsdcSucceedsCompPCVMover() public {
        vm.prank(compoundPCVMover);
    }

    function testSwapUsdcToDaiFailsNoLiquidity() public {}

    function testSwapDaiToUsdcFailsNoLiquidity() public {}

    function testSwapUsdcToDaiFailsUnauthorized() public {}

    function testSwapDaiToUsdcFailsUnauthorized() public {}
}
