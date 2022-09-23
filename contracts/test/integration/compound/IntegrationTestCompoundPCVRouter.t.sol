pragma solidity ^0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {Vm} from "../../unit/utils/Vm.sol";
import {Core} from "../../../core/Core.sol";
import {CToken} from "../../../pcv/compound/CToken.sol";
import {DSTest} from "../../unit/utils/DSTest.sol";
import {IDSSPSM} from "./../../../pcv/maker/IDSSPSM.sol";
import {stdError} from "../../unit/utils/StdLib.sol";
import {MockERC20} from "../../../mock/MockERC20.sol";
import {TribeRoles} from "../../../core/TribeRoles.sol";
import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {ArbitrumAddresses} from "../fixtures/ArbitrumAddresses.sol";
import {CompoundPCVRouter} from "../../../pcv/compound/CompoundPCVRouter.sol";
import {ERC20CompoundPCVDeposit} from "../../../pcv/compound/ERC20CompoundPCVDeposit.sol";

contract CompoundPCVRouterIntegrationTest is DSTest {
    using SafeCast for *;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    Core private core = Core(MainnetAddresses.CORE);
    IERC20 private usdc = IERC20(MainnetAddresses.USDC);
    IERC20 private dai = IERC20(MainnetAddresses.DAI);
    address private governor = MainnetAddresses.GOVERNOR;

    CToken private cDai = CToken(MainnetAddresses.CDAI);
    CToken private cUsdc = CToken(MainnetAddresses.CUSDC);

    IDSSPSM public immutable daiPSM =
        IDSSPSM(0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A);

    CompoundPCVRouter private compoundRouter;

    ERC20CompoundPCVDeposit private daiDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_DAI_PCV_DEPOSIT);
    ERC20CompoundPCVDeposit private usdcDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT);

    address public immutable pcvGuard = MainnetAddresses.EOA_1;
    PCVGuardian public immutable pcvGuardian =
        PCVGuardian(MainnetAddresses.PCV_GUARDIAN);

    address public constant makerWard =
        0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB;

    /// @notice scaling factor for USDC
    uint256 public constant USDC_SCALING_FACTOR = 1e12;

    function setUp() public {
        compoundRouter = new CompoundPCVRouter(
            address(core),
            daiDeposit,
            usdcDeposit
        );

        vm.prank(governor);
        core.grantPCVController(address(compoundRouter));

        cDai.accrueInterest();
        cUsdc.accrueInterest();
    }

    function testSetup() public {
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
        uint256 usdcStartingBalance = usdcDeposit.balance();

        vm.prank(governor);
        compoundRouter.swapDaiForUsdc(withdrawAmount); /// withdraw all balance

        assertApproxEq(
            usdcDeposit.balance().toInt256(),
            (withdrawAmount / USDC_SCALING_FACTOR + usdcStartingBalance)
                .toInt256(),
            0
        );
        assertTrue(daiDeposit.balance() < 1e10); /// assert only dust remains
    }

    function testSwapUsdcToDaiSucceeds() public {
        uint256 withdrawAmount = usdcDeposit.balance();
        uint256 daiStartingBalance = daiDeposit.balance();

        vm.prank(governor);
        compoundRouter.swapUsdcForDai(withdrawAmount); /// withdraw all balance

        assertApproxEq(
            daiDeposit.balance().toInt256(),
            (withdrawAmount * USDC_SCALING_FACTOR + daiStartingBalance)
                .toInt256(),
            0
        );

        assertTrue(usdcDeposit.balance() < 1e3); /// assert only dust remains
    }

    function testSwapUsdcToDaiSucceedsPCVGuard() public {
        uint256 withdrawAmount = usdcDeposit.balance();
        uint256 daiStartingBalance = daiDeposit.balance();

        vm.prank(pcvGuard);
        compoundRouter.swapUsdcForDai(withdrawAmount); /// withdraw all balance

        assertApproxEq(
            daiDeposit.balance().toInt256(),
            (withdrawAmount * USDC_SCALING_FACTOR + daiStartingBalance)
                .toInt256(),
            0
        );
        assertTrue(usdcDeposit.balance() < 1e3); /// assert only dust remains
    }

    function testSwapDaiToUsdcSucceedsPCVGuard() public {
        uint256 withdrawAmount = daiDeposit.balance();
        uint256 usdcStartingBalance = usdcDeposit.balance();

        vm.prank(pcvGuard);
        compoundRouter.swapDaiForUsdc(withdrawAmount); /// withdraw all balance

        assertApproxEq(
            usdcDeposit.balance().toInt256(),
            (withdrawAmount / USDC_SCALING_FACTOR + usdcStartingBalance)
                .toInt256(),
            0
        );
        assertTrue(daiDeposit.balance() < 1e10); /// assert only dust remains
    }

    function testSwapUsdcToDaiFailsNoLiquidity() public {
        uint256 usdcBalance = usdc.balanceOf(
            MainnetAddresses.KRAKEN_USDC_WHALE
        );
        vm.prank(MainnetAddresses.KRAKEN_USDC_WHALE);
        usdc.transfer(address(usdcDeposit), usdcBalance);
        usdcDeposit.deposit();

        uint256 withdrawAmount = usdcDeposit.balance();
        vm.startPrank(pcvGuard);
        pcvGuardian.withdrawAllToSafeAddress(address(usdcDeposit)); /// pull all funds from usdc pcv deposit
        vm.expectRevert("CompoundPCVDeposit: redeem error"); /// CUSDC has old cToken implementation that fails without reverting
        compoundRouter.swapUsdcForDai(withdrawAmount); /// withdraw all balance
        vm.stopPrank();
    }

    function testSwapDaiToUsdcFailsNoLiquidity() public {
        uint256 withdrawAmount = daiDeposit.balance();
        vm.startPrank(pcvGuard);
        pcvGuardian.withdrawAllToSafeAddress(address(daiDeposit)); /// pull all funds from dai pcv deposit
        vm.expectRevert(stdError.arithmeticError); /// CDAI has new cToken implementation that fails with a revert
        compoundRouter.swapDaiForUsdc(withdrawAmount); /// withdraw all balance
        vm.stopPrank();
    }

    function testSwapUsdcToDaiFailsUnauthorized() public {
        uint256 withdrawAmount = usdcDeposit.balance();
        vm.expectRevert("UNAUTHORIZED");
        compoundRouter.swapUsdcForDai(withdrawAmount);
    }

    function testSwapDaiToUsdcFailsUnauthorized() public {
        uint256 withdrawAmount = daiDeposit.balance();
        vm.expectRevert("UNAUTHORIZED");
        compoundRouter.swapDaiForUsdc(withdrawAmount);
    }

    function testSwapUsdcToDaiFailsTinNonZero() public {
        vm.prank(makerWard);
        daiPSM.file(bytes32("tin"), 1);

        uint256 withdrawAmount = usdcDeposit.balance();

        vm.prank(pcvGuard);
        vm.expectRevert("CompoundPCVRouter: maker fee not 0");
        compoundRouter.swapUsdcForDai(withdrawAmount);
    }

    function testSwapDaiToUsdcFailsToutNonZero() public {
        vm.prank(makerWard);
        daiPSM.file(bytes32("tout"), 1);

        uint256 withdrawAmount = daiDeposit.balance();

        vm.prank(pcvGuard);
        vm.expectRevert("CompoundPCVRouter: maker fee not 0");
        compoundRouter.swapDaiForUsdc(withdrawAmount); /// withdraw all balance
    }
}
