// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {MockPCVDepositV2} from "../../mock/MockPCVDepositV2.sol";
import {IPCVDeposit} from "../../pcv/IPCVDeposit.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {OraclePassThrough} from "../../oracle/OraclePassThrough.sol";
import {ICore} from "../../core/ICore.sol";
import {Core} from "../../core/Core.sol";
import {IVolt, Volt} from "../../volt/Volt.sol";
import {PriceBoundPSM, PegStabilityModule} from "../../peg/PriceBoundPSM.sol";
import {getCore, getMainnetAddresses, VoltTestAddresses} from "../unit/utils/Fixtures.sol";
import {ERC20CompoundPCVDeposit} from "../../pcv/compound/ERC20CompoundPCVDeposit.sol";
import {Vm} from "./../unit/utils/Vm.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {Constants} from "../../Constants.sol";
import {vip7} from "./vip/vip7.sol";
import {TimelockSimulation} from "./utils/TimelockSimulation.sol";
import {IPCVGuardian} from "../../pcv/IPCVGuardian.sol";

contract IntegrationTestPriceBoundPSMDaiTest is TimelockSimulation, vip7 {
    using SafeCast for *;
    PriceBoundPSM private psm;
    ICore private core = ICore(MainnetAddresses.CORE);
    IVolt private volt = IVolt(MainnetAddresses.VOLT);
    IVolt private dai = IVolt(MainnetAddresses.DAI);
    IVolt private underlyingToken = dai;

    uint256 public constant mintAmount = 1_000_000e18;
    OraclePassThrough public oracle =
        OraclePassThrough(MainnetAddresses.ORACLE_PASS_THROUGH);

    uint256 voltFloorPrice = 9_000; /// 1 volt for .9 dai is the max allowable price
    uint256 voltCeilingPrice = 10_000; /// 1 volt for 1 dai is the minimum price

    function setUp() public {
        psm = PriceBoundPSM(MainnetAddresses.VOLT_DAI_PSM);

        vm.startPrank(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        dai.transfer(address(this), mintAmount);
        dai.transfer(address(psm), mintAmount * 2);
        vm.stopPrank();

        vm.startPrank(MainnetAddresses.GOVERNOR);
        core.grantMinter(MainnetAddresses.GOVERNOR);
        /// mint VOLT to the user
        volt.mint(address(this), mintAmount);
        core.revokeMinter(MainnetAddresses.GOVERNOR);
        vm.stopPrank();
    }

    /// @notice PSM is set up correctly
    function testSetUpCorrectly() public {
        assertTrue(psm.doInvert());
        assertTrue(psm.isPriceValid());
        assertEq(psm.floor(), voltFloorPrice);
        assertEq(psm.ceiling(), voltCeilingPrice);
        assertEq(address(psm.oracle()), address(oracle));
        assertEq(address(psm.backupOracle()), address(0));
        assertEq(psm.decimalsNormalizer(), 0);
        assertEq(address(psm.underlyingToken()), address(dai));
    }

    /// @notice PSM is set up correctly and view functions are working
    function testGetRedeemAmountOut(uint128 amountVoltIn) public {
        uint256 currentPegPrice = oracle.getCurrentOraclePrice();

        uint256 amountOut = (amountVoltIn * currentPegPrice) / 1e18;

        assertApproxEq(
            psm.getRedeemAmountOut(amountVoltIn).toInt256(),
            amountOut.toInt256(),
            0
        );
    }

    /// @notice PSM is set up correctly and view functions are working
    function testGetMintAmountOut(uint256 amountDaiIn) public {
        vm.assume(dai.balanceOf(address(this)) > amountDaiIn);
        uint256 currentPegPrice = oracle.getCurrentOraclePrice();

        uint256 amountOut = (amountDaiIn * 1e18) / currentPegPrice;

        assertApproxEq(
            psm.getMintAmountOut(amountDaiIn).toInt256(),
            amountOut.toInt256(),
            0
        );
    }

    /// @notice pcv deposit receives underlying token on mint
    function testSwapUnderlyingForVoltAfterPriceIncrease() public {
        uint256 amountStableIn = 101_000;
        uint256 amountVoltOut = psm.getMintAmountOut(amountStableIn);

        uint256 startingUserVoltBalance = volt.balanceOf(address(this));
        uint256 startingPSMUnderlyingBalance = underlyingToken.balanceOf(
            address(psm)
        );

        underlyingToken.approve(address(psm), amountStableIn);
        psm.mint(address(this), amountStableIn, amountVoltOut);

        uint256 endingUserVoltBalance = volt.balanceOf(address(this));
        uint256 endingPSMUnderlyingBalance = underlyingToken.balanceOf(
            address(psm)
        );

        assertEq(
            endingPSMUnderlyingBalance - startingPSMUnderlyingBalance,
            amountStableIn
        );
        assertEq(
            endingUserVoltBalance - startingUserVoltBalance,
            amountVoltOut
        );
    }

    /// @notice pcv deposit receives underlying token on mint
    function testSwapUnderlyingForVolt() public {
        uint256 userStartingVoltBalance = volt.balanceOf(address(this));
        uint256 minAmountOut = psm.getMintAmountOut(mintAmount);
        uint256 startingPSMUnderlyingBalance = underlyingToken.balanceOf(
            address(psm)
        );

        underlyingToken.approve(address(psm), mintAmount);
        uint256 amountVoltOut = psm.mint(
            address(this),
            mintAmount,
            minAmountOut
        );

        uint256 endingUserVOLTBalance = volt.balanceOf(address(this));
        uint256 endingPSMUnderlyingBalance = underlyingToken.balanceOf(
            address(psm)
        );

        assertEq(
            endingUserVOLTBalance,
            amountVoltOut + userStartingVoltBalance
        );
        assertEq(
            endingPSMUnderlyingBalance - startingPSMUnderlyingBalance,
            mintAmount
        );
    }

    /// @notice pcv deposit gets depleted on redeem
    function testSwapVoltForUnderlying() public {
        uint256 startingUserUnderlyingBalance = underlyingToken.balanceOf(
            address(this)
        );
        uint256 startingPSMUnderlyingBalance = underlyingToken.balanceOf(
            address(psm)
        );
        volt.approve(address(psm), mintAmount);
        uint256 amountOut = psm.redeem(address(this), mintAmount, mintAmount);

        uint256 endingUserVOLTBalance = volt.balanceOf(address(this));
        uint256 endingUserUnderlyingBalance = underlyingToken.balanceOf(
            address(this)
        );
        uint256 endingPSMUnderlyingBalance = underlyingToken.balanceOf(
            address(psm)
        );

        assertEq(
            startingPSMUnderlyingBalance - endingPSMUnderlyingBalance,
            amountOut
        );
        assertEq(endingUserVOLTBalance, 0);
        assertEq(
            endingUserUnderlyingBalance - startingUserUnderlyingBalance,
            amountOut
        );
    }

    /// @notice redeem fails without approval
    function testSwapVoltForUnderlyingFailsWithoutApproval() public {
        vm.expectRevert(bytes("ERC20: transfer amount exceeds allowance"));

        psm.redeem(address(this), mintAmount, mintAmount);
    }

    /// @notice mint fails without approval
    function testSwapUnderlyingForVoltFailsWithoutApproval() public {
        vm.expectRevert(bytes("Dai/insufficient-allowance"));

        psm.mint(address(this), mintAmount, 0);
    }

    /// @notice withdraw erc20 fails without correct permissions
    function testERC20WithdrawFailure() public {
        vm.expectRevert(bytes("CoreRef: Caller is not a PCV controller"));

        psm.withdrawERC20(address(underlyingToken), address(this), 100);
    }

    /// @notice withdraw erc20 succeeds with correct permissions
    function testERC20WithdrawSuccess() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        core.grantPCVController(address(this));

        uint256 startingBalance = underlyingToken.balanceOf(address(this));
        psm.withdrawERC20(address(underlyingToken), address(this), mintAmount);
        uint256 endingBalance = underlyingToken.balanceOf(address(this));

        assertEq(endingBalance - startingBalance, mintAmount);
    }

    /// @notice redeem fails when paused
    function testRedeemFailsWhenPaused() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        psm.pauseRedeem();

        vm.expectRevert(bytes("PegStabilityModule: Redeem paused"));
        psm.redeem(address(this), 100, 100);
    }

    /// @notice mint fails when paused
    function testMintFailsWhenPaused() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        psm.pauseMint();

        vm.expectRevert(bytes("PegStabilityModule: Minting paused"));
        psm.mint(address(this), 100, 100);
    }
}
