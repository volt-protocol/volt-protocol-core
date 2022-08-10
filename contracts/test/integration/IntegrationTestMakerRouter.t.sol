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
        dai.transfer(address(feiPSM), mintAmount);

        vm.prank(MainnetAddresses.FEI_GOVERNOR);
        fei.mint(address(this), mintAmount);

        vm.prank(MainnetAddresses.GOVERNOR);
        core.grantGovernor(address(this));
    }

    function testSwapFeiForDai(uint64 amountFeiIn) public {
        vm.assume(amountFeiIn > 1e18);

        uint256 minDaiAmountOut = feiPSM.getRedeemAmountOut(amountFeiIn);
        makerRouter.swapFeiForDai(amountFeiIn, minDaiAmountOut);

        assertEq(minDaiAmountOut, dai.balanceOf(address(makerRouter)));
    }

    function testSwapFeiForUsdc(uint64 amountFeiIn) public {
        vm.assume(amountFeiIn > 1e18);

        uint256 minDaiAmountOut = feiPSM.getRedeemAmountOut(amountFeiIn);
        makerRouter.swapFeiForUsdc(amountFeiIn, minDaiAmountOut);

        assertEq(
            (minDaiAmountOut / 1e12),
            usdc.balanceOf(address(makerRouter))
        );
    }

    function testSwapFeiForUsdcAndDai() public {
        uint256 minDaiAmountOut = feiPSM.getRedeemAmountOut(mintAmount);
        makerRouter.swapFeiForUsdcAndDai(mintAmount, minDaiAmountOut, 50);

        assertEq((minDaiAmountOut / 2), dai.balanceOf(address(makerRouter)));
        assertEq(
            ((minDaiAmountOut / 2) / 1e12),
            usdc.balanceOf(address(makerRouter))
        );
    }

    function testTransferAllDai() public {
        uint256 minDaiAmountOut = feiPSM.getRedeemAmountOut(mintAmount);

        makerRouter.swapFeiForDai(mintAmount, minDaiAmountOut);
        makerRouter.transferAllToken(address(this), address(dai));

        assertEq(minDaiAmountOut, dai.balanceOf(address(this)));
    }

    function testTransferAllUsdc() public {
        uint256 minDaiAmountOut = feiPSM.getRedeemAmountOut(mintAmount);

        makerRouter.swapFeiForUsdc(mintAmount, minDaiAmountOut);
        makerRouter.transferAllToken(address(this), address(usdc));

        assertEq((minDaiAmountOut / 1e12), usdc.balanceOf(address(this)));
    }
}
