// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ICore} from "../../core/ICore.sol";
import {IVolt} from "../../volt/Volt.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {vip8} from "./vip/vip8.sol";
import {TimelockSimulation} from "./utils/TimelockSimulation.sol";
import {PriceBoundPSM} from "../../peg/PriceBoundPSM.sol";
import {IPCVGuardian} from "../../pcv/IPCVGuardian.sol";

contract IntegrationTestVIP8 is TimelockSimulation, vip8 {
    using SafeCast for *;
    PriceBoundPSM private psm;

    ICore private core = ICore(MainnetAddresses.CORE);
    IERC20 dai = IERC20(MainnetAddresses.DAI);
    IVolt volt = IVolt(MainnetAddresses.VOLT);

    uint256 public constant mintAmount = 2_000_000e18;

    function setUp() public {
        psm = PriceBoundPSM(MainnetAddresses.VOLT_DAI_PSM);

        vm.startPrank(MainnetAddresses.GOVERNOR);
        core.grantMinter(MainnetAddresses.GOVERNOR);
        /// mint VOLT to the user
        volt.mint(address(psm), mintAmount);
        volt.mint(address(this), mintAmount);
        core.revokeMinter(MainnetAddresses.GOVERNOR);
        vm.stopPrank();

        vm.prank(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        dai.transfer(address(this), mintAmount);

        mainnetSetup();
        simulate(
            getMainnetProposal(),
            TimelockController(payable(MainnetAddresses.TIMELOCK_CONTROLLER)),
            IPCVGuardian(MainnetAddresses.PCV_GUARDIAN),
            MainnetAddresses.GOVERNOR,
            MainnetAddresses.EOA_1,
            vm,
            false
        );
    }

    function testRedeem(uint80 amountVoltIn) public {
        uint256 startingUserDaiBalance = dai.balanceOf(address(this));
        uint256 startingPSMDaiBalance = dai.balanceOf(address(psm));
        uint256 startingUserVoltBalance = volt.balanceOf(address(this));
        uint256 startingPSMVoltBalace = volt.balanceOf(address(psm));

        volt.approve(address(psm), amountVoltIn);

        uint256 minAmountOut = psm.getRedeemAmountOut(amountVoltIn);
        uint256 amountOut = psm.redeem(
            address(this),
            amountVoltIn,
            minAmountOut
        );

        uint256 endingUserVOLTBalance = volt.balanceOf(address(this));
        uint256 endingUserDaiBalance = dai.balanceOf(address(this));
        uint256 endingPSMDaiBalance = dai.balanceOf(address(psm));
        uint256 endingPSMVoltBalance = volt.balanceOf(address(psm));

        assertEq(endingPSMDaiBalance, startingPSMDaiBalance - amountOut);
        assertEq(endingUserVOLTBalance, startingUserVoltBalance - amountVoltIn);
        assertEq(endingUserDaiBalance, startingUserDaiBalance + amountOut);
        assertEq(endingPSMVoltBalance, startingPSMVoltBalace + amountVoltIn);
    }

    function testMint(uint80 amountDaiIn) public {
        uint256 startingUserVoltBalance = volt.balanceOf(address(this));
        uint256 startingUserDaiBalance = dai.balanceOf(address(this));
        uint256 startingPSMVoltBalance = volt.balanceOf(address(psm));
        uint256 startingPSMDaiBalance = dai.balanceOf(address(psm));

        dai.approve(address(psm), amountDaiIn);
        uint256 amountOut = psm.getMintAmountOut(amountDaiIn);
        psm.mint(address(this), amountDaiIn, amountOut);

        uint256 endingUserVoltBalance = volt.balanceOf(address(this));
        uint256 endingUserDaiBalance = dai.balanceOf(address(this));
        uint256 endingPSMVoltBalance = volt.balanceOf(address(psm));
        uint256 endingPSMDaiBalance = dai.balanceOf(address(psm));

        assertEq(endingPSMVoltBalance, startingPSMVoltBalance - amountOut);
        assertEq(endingUserVoltBalance, startingUserVoltBalance + amountOut);
        assertEq(endingUserDaiBalance, startingUserDaiBalance - amountDaiIn);
        assertEq(endingPSMDaiBalance, startingPSMDaiBalance + amountDaiIn);
    }
}
