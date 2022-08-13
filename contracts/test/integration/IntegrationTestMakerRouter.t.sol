//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;
import {DSTest} from "../unit/utils/DSTest.sol";
import {Vm} from "../unit/utils/Vm.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {IDSSPSM} from "../../pcv/maker/IDSSPSM.sol";
import {MakerRouter} from "../../pcv/maker/MakerRouter.sol";
import {PegStabilityModule} from "../../peg/PegStabilityModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVolt} from "../../volt/IVolt.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Core} from "../../core/Core.sol";
import {Constants} from "../../Constants.sol";

contract IntegrationTestMakerRouter is DSTest {
    using SafeCast for *;

    MakerRouter private makerRouter;

    Core private core = Core(MainnetAddresses.CORE);
    IDSSPSM private daiPSM = IDSSPSM(MainnetAddresses.MAKER_DAI_USDC_PSM);
    PegStabilityModule private feiPSM =
        PegStabilityModule(MainnetAddresses.FEI_DAI_PSM);

    IERC20 private dai = IERC20(MainnetAddresses.DAI);
    IVolt private fei = IVolt(MainnetAddresses.FEI);
    IERC20 private usdc = IERC20(MainnetAddresses.USDC);

    Vm public constant vm = Vm(HEVM_ADDRESS);

    uint256 public constant USDC_SCALING_FACTOR = 1e12;

    uint256 public constant mintAmount = 200_000_000e18;

    function setUp() public {
        makerRouter = new MakerRouter(
            MainnetAddresses.CORE,
            daiPSM,
            feiPSM,
            dai,
            fei
        );

        fei.approve(address(makerRouter), type(uint256).max);
        dai.approve(address(makerRouter), type(uint256).max);

        vm.prank(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        dai.transfer(address(feiPSM), mintAmount + 100_000_000e18);

        vm.prank(MainnetAddresses.FEI_GOVERNOR);
        fei.mint(address(this), mintAmount);
    }

    function testSwapFeiForDai(uint64 amountFeiIn) public {
        vm.assume(amountFeiIn > 1e18);

        vm.prank(MainnetAddresses.GOVERNOR);
        core.grantGovernor(address(this));

        uint256 minDaiAmountOut = feiPSM.getRedeemAmountOut(amountFeiIn);
        makerRouter.swapFeiForDai(amountFeiIn, minDaiAmountOut, address(this));

        assertEq(minDaiAmountOut, dai.balanceOf(address(this)));
    }

    function testSwapFeiForDaiPCVController(uint64 amountFeiIn) public {
        vm.assume(amountFeiIn > 1e18);

        vm.prank(MainnetAddresses.GOVERNOR);
        core.grantPCVController(address(this));

        uint256 minDaiAmountOut = feiPSM.getRedeemAmountOut(amountFeiIn);
        makerRouter.swapFeiForDai(amountFeiIn, minDaiAmountOut, address(this));

        assertEq(minDaiAmountOut, dai.balanceOf(address(this)));
    }

    function testSwapFeiForUsdc(uint64 amountFeiIn) public {
        vm.assume(amountFeiIn > 1e18);

        vm.prank(MainnetAddresses.GOVERNOR);
        core.grantGovernor(address(this));

        uint256 minDaiAmountOut = feiPSM.getRedeemAmountOut(amountFeiIn);
        makerRouter.swapFeiForUsdc(amountFeiIn, minDaiAmountOut, address(this));

        assertEq(
            (minDaiAmountOut / USDC_SCALING_FACTOR),
            usdc.balanceOf(address(this))
        );
    }

    function testSwapFeiForUsdcPCVController(uint64 amountFeiIn) public {
        vm.assume(amountFeiIn > 1e18);

        vm.prank(MainnetAddresses.GOVERNOR);
        core.grantPCVController(address(this));

        uint256 minDaiAmountOut = feiPSM.getRedeemAmountOut(amountFeiIn);
        makerRouter.swapFeiForUsdc(amountFeiIn, minDaiAmountOut, address(this));

        assertEq(
            (minDaiAmountOut / USDC_SCALING_FACTOR),
            usdc.balanceOf(address(this))
        );
    }

    function testSwapFeiForUsdcAndDai(uint64 amountFeiIn, uint16 ratioUSDC)
        public
    {
        vm.assume(amountFeiIn > 1e18);
        vm.assume(ratioUSDC < 10_000 && ratioUSDC > 0);

        vm.prank(MainnetAddresses.GOVERNOR);
        core.grantGovernor(address(this));

        uint256 minDaiAmountOut = feiPSM.getRedeemAmountOut(amountFeiIn);
        makerRouter.swapFeiForUsdcAndDai(
            amountFeiIn,
            minDaiAmountOut,
            address(this),
            address(this),
            ratioUSDC
        );

        uint256 usdcAmount = (minDaiAmountOut * ratioUSDC) /
            Constants.BASIS_POINTS_GRANULARITY;

        assertEq((minDaiAmountOut - usdcAmount), dai.balanceOf(address(this)));
        assertEq(
            (usdcAmount / USDC_SCALING_FACTOR),
            usdc.balanceOf(address(this))
        );
    }

    function testSwapFeiForUsdcAndDaiPCVController(
        uint64 amountFeiIn,
        uint16 ratioUSDC
    ) public {
        vm.assume(amountFeiIn > 1e18);
        vm.assume(ratioUSDC < 10_000 && ratioUSDC > 0);

        vm.prank(MainnetAddresses.GOVERNOR);
        core.grantPCVController(address(this));

        uint256 minDaiAmountOut = feiPSM.getRedeemAmountOut(amountFeiIn);
        makerRouter.swapFeiForUsdcAndDai(
            amountFeiIn,
            minDaiAmountOut,
            address(this),
            address(this),
            ratioUSDC
        );

        uint256 usdcAmount = (minDaiAmountOut * ratioUSDC) /
            Constants.BASIS_POINTS_GRANULARITY;

        assertEq((minDaiAmountOut - usdcAmount), dai.balanceOf(address(this)));
        assertEq(
            (usdcAmount / USDC_SCALING_FACTOR),
            usdc.balanceOf(address(this))
        );
    }

    function testSwapAllFeiForDai() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        core.grantGovernor(address(this));

        makerRouter.swapAllFeiForDai(address(this));

        assertEq(
            dai.balanceOf(address(this)),
            feiPSM.getRedeemAmountOut(mintAmount)
        );
    }

    function testSwapAllFeiForDaiPCVController() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        core.grantPCVController(address(this));

        makerRouter.swapAllFeiForDai(address(this));

        assertEq(
            dai.balanceOf(address(this)),
            feiPSM.getRedeemAmountOut(mintAmount)
        );
    }

    function testSwapAllFeiForUsdc() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        core.grantGovernor(address(this));
        makerRouter.swapAllFeiForUsdc(address(this));

        assertEq(
            usdc.balanceOf(address(this)),
            feiPSM.getRedeemAmountOut(mintAmount) / USDC_SCALING_FACTOR
        );
    }

    function testSwapAllFeiForUsdcPCVController() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        core.grantPCVController(address(this));
        makerRouter.swapAllFeiForUsdc(address(this));

        assertEq(
            usdc.balanceOf(address(this)),
            feiPSM.getRedeemAmountOut(mintAmount) / USDC_SCALING_FACTOR
        );
    }

    function testSwapAllFeiForUsdcAndDai(uint16 ratioUSDC) public {
        vm.assume(ratioUSDC < 10_000 && ratioUSDC > 0);

        vm.prank(MainnetAddresses.GOVERNOR);
        core.grantGovernor(address(this));

        uint256 minDaiAmountOut = feiPSM.getRedeemAmountOut(mintAmount);

        makerRouter.swapAllFeiForUsdcAndDai(
            address(this),
            address(this),
            ratioUSDC
        );
        uint256 usdcAmount = (minDaiAmountOut * ratioUSDC) /
            Constants.BASIS_POINTS_GRANULARITY;

        assertEq(
            usdc.balanceOf(address(this)),
            usdcAmount / USDC_SCALING_FACTOR
        );
        assertEq(dai.balanceOf(address(this)), minDaiAmountOut - usdcAmount);
    }

    function testSwapAllFeiForUsdcAndDaiPCVController(uint16 ratioUSDC) public {
        vm.assume(ratioUSDC < 10_000 && ratioUSDC > 0);

        vm.prank(MainnetAddresses.GOVERNOR);
        core.grantPCVController(address(this));

        uint256 minDaiAmountOut = feiPSM.getRedeemAmountOut(mintAmount);

        makerRouter.swapAllFeiForUsdcAndDai(
            address(this),
            address(this),
            ratioUSDC
        );
        uint256 usdcAmount = (minDaiAmountOut * ratioUSDC) /
            Constants.BASIS_POINTS_GRANULARITY;

        assertEq(
            usdc.balanceOf(address(this)),
            usdcAmount / USDC_SCALING_FACTOR
        );
        assertEq(dai.balanceOf(address(this)), minDaiAmountOut - usdcAmount);
    }

    function testSwapForDaiRevertWithoutPermissions() public {
        uint256 minDaiAmountOut = feiPSM.getRedeemAmountOut(mintAmount);

        vm.expectRevert("UNAUTHORIZED");
        makerRouter.swapFeiForDai(mintAmount, minDaiAmountOut, address(this));
    }

    function testSwapAllForDaiRevertWithoutPermissions() public {
        vm.expectRevert("UNAUTHORIZED");
        makerRouter.swapAllFeiForDai(address(this));
    }

    function testSwapForUsdcRevertWithoutPermissions() public {
        uint256 minDaiAmountOut = feiPSM.getRedeemAmountOut(mintAmount);

        vm.expectRevert("UNAUTHORIZED");
        makerRouter.swapFeiForUsdc(mintAmount, minDaiAmountOut, address(this));
    }

    function testSwapAllForUsdcRevertWithoutPermissions() public {
        vm.expectRevert("UNAUTHORIZED");
        makerRouter.swapAllFeiForUsdc(address(this));
    }

    function testSwapForUsdcAndDaiRevertWithoutPermissions() public {
        uint256 minDaiAmountOut = feiPSM.getRedeemAmountOut(mintAmount);

        vm.expectRevert("UNAUTHORIZED");
        makerRouter.swapFeiForUsdcAndDai(
            mintAmount,
            minDaiAmountOut,
            address(this),
            address(this),
            5000
        );
    }

    function testSwapAllForUsdcAndDaiRevertWithoutPermissions() public {
        vm.expectRevert("UNAUTHORIZED");
        makerRouter.swapAllFeiForUsdcAndDai(address(this), address(this), 5000);
    }

    function testInvalidAboveUSDCRatio() public {
        uint256 minDaiAmountOut = feiPSM.getRedeemAmountOut(mintAmount);

        vm.prank(MainnetAddresses.GOVERNOR);
        core.grantGovernor(address(this));

        vm.expectRevert("MakerRouter: Invalid USDC Ratio");
        makerRouter.swapFeiForUsdcAndDai(
            mintAmount,
            minDaiAmountOut,
            address(this),
            address(this),
            10000
        );
    }

    function testInvalidBelowUSDCRatio() public {
        uint256 minDaiAmountOut = feiPSM.getRedeemAmountOut(mintAmount);

        vm.prank(MainnetAddresses.GOVERNOR);
        core.grantGovernor(address(this));

        vm.expectRevert("MakerRouter: Invalid USDC Ratio");
        makerRouter.swapFeiForUsdcAndDai(
            mintAmount,
            minDaiAmountOut,
            address(this),
            address(this),
            0
        );
    }

    function testRevertWhenMinimumFeiAmountNotDeposited() public {
        uint256 amountFeiIn = 1e17;
        vm.prank(MainnetAddresses.GOVERNOR);
        core.grantPCVController(address(this));

        uint256 minDaiAmountOut = feiPSM.getRedeemAmountOut(amountFeiIn);

        vm.expectRevert("MakerRouter: Must deposit at least 1 FEI");
        makerRouter.swapFeiForDai(amountFeiIn, minDaiAmountOut, address(this));
    }

    function testWithdrawERC20(uint64 amountDai) public {
        vm.prank(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        dai.transfer(address(makerRouter), amountDai);

        uint256 routerDaiBalance = dai.balanceOf(address(makerRouter));
        uint256 userInitialDaiBalance = dai.balanceOf(address(this));

        vm.prank(MainnetAddresses.GOVERNOR);
        core.grantPCVController(address(this));

        makerRouter.withdrawERC20(address(dai), amountDai, address(this));
        uint256 userFinalBalance = dai.balanceOf(address(this));

        assertEq(userFinalBalance, routerDaiBalance + userInitialDaiBalance);
    }
}
