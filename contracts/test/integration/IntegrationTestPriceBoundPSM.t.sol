// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {MockPCVDepositV2} from "../../mock/MockPCVDepositV2.sol";
import {IPCVDeposit} from "../../pcv/IPCVDeposit.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {OraclePassThrough} from "../../oracle/OraclePassThrough.sol";
import {ICore} from "../../core/ICore.sol";
import {Core} from "../../core/Core.sol";
import {IVolt, Volt} from "../../volt/Volt.sol";
import {PegStabilityModule} from "../../peg/PegStabilityModule.sol";
import {getCore, getMainnetAddresses, VoltTestAddresses} from "../unit/utils/Fixtures.sol";
import {ERC20CompoundPCVDeposit} from "../../pcv/compound/ERC20CompoundPCVDeposit.sol";
import {Vm} from "./../unit/utils/Vm.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {Constants} from "../../Constants.sol";

contract IntegrationTestPriceBoundPSMTest is DSTest {
    using SafeCast for *;
    PegStabilityModule private psm;
    ICore private core = ICore(MainnetAddresses.CORE);
    ICore private feiCore = ICore(MainnetAddresses.FEI_CORE);
    IVolt private volt = IVolt(MainnetAddresses.VOLT);
    IVolt private fei = IVolt(MainnetAddresses.FEI);
    IVolt private underlyingToken = fei;

    /// --------------- Minting Params ---------------

    uint256 public constant mintAmount = 10_000_000e18;

    /// @notice fei dai psm address
    address public immutable feiDaiPsm = MainnetAddresses.FINAL_FEI_DAI_PSM;

    /// @notice Oracle Pass Through contract
    OraclePassThrough public oracle =
        OraclePassThrough(MainnetAddresses.DEPRECATED_ORACLE_PASS_THROUGH);

    Vm public constant vm = Vm(HEVM_ADDRESS);

    uint128 voltFloorPrice = 1.05e18; /// 1 volt for 1.05 fei is the min price
    uint128 voltCeilingPrice = 1.1e18; /// 1 volt for 1.1 fei is the max price

    function setUp() public {
        /// create PSM
        psm = new PegStabilityModule(
            address(core),
            address(oracle),
            address(0),
            0,
            false,
            IERC20(address(fei)),
            voltFloorPrice,
            voltCeilingPrice
        );

        vm.prank(feiDaiPsm);
        fei.mint(address(this), mintAmount);

        vm.startPrank(MainnetAddresses.GOVERNOR);

        /// grant the PSM the PCV Controller role
        core.grantMinter(MainnetAddresses.GOVERNOR);
        /// mint VOLT to the user
        volt.mint(address(psm), mintAmount);
        volt.mint(address(this), mintAmount);
        vm.stopPrank();

        vm.prank(feiDaiPsm);
        fei.mint(address(psm), mintAmount * 100_000);
    }

    /// @notice PSM inverts price
    function testSetup() public {
        assertTrue(!psm.doInvert());
        assertEq(psm.decimalsNormalizer(), 0);
    }

    /// @notice PSM is set up correctly and view functions are working
    function testGetRedeemAmountOut() public {
        uint256 currentPegPrice = oracle.getCurrentOraclePrice();
        uint256 fee = 0;

        uint256 amountOut = ((mintAmount * currentPegPrice) / 1e18) - fee;

        assertApproxEq(
            psm.getRedeemAmountOut(mintAmount).toInt256(),
            amountOut.toInt256(),
            1
        );
    }

    /// @notice PSM is set up correctly and view functions are working
    function testGetMaxMintAmountOut() public {
        uint256 startingBalance = volt.balanceOf(address(psm));
        assertEq(psm.getMaxMintAmountOut(), startingBalance);

        vm.startPrank(MainnetAddresses.GOVERNOR);
        volt.mint(address(psm), mintAmount);
        vm.stopPrank();

        assertEq(psm.getMaxMintAmountOut(), mintAmount + startingBalance);
    }

    /// @notice PSM is set up correctly and view functions are working
    function testGetMintAmountOut() public {
        uint256 currentPegPrice = oracle.getCurrentOraclePrice();

        uint256 amountOut = (mintAmount * 1e18) / currentPegPrice;

        assertApproxEq(
            psm.getMintAmountOut(mintAmount).toInt256(),
            amountOut.toInt256(),
            1
        );
    }

    /// @notice pcv deposit receives underlying token on mint
    function testSwapUnderlyingForVoltAfterPriceIncrease() public {
        uint256 amountStableIn = 101_000;
        uint256 amountVoltOut = psm.getMintAmountOut(amountStableIn);

        underlyingToken.approve(address(psm), amountStableIn);
        psm.mint(address(this), amountStableIn, amountVoltOut);

        uint256 endingUserVoltBalance = volt.balanceOf(address(this));
        uint256 endingPSMUnderlyingBalance = underlyingToken.balanceOf(
            address(psm)
        );

        assertEq(
            endingPSMUnderlyingBalance,
            amountStableIn + mintAmount * 100_000
        );
        assertEq(endingUserVoltBalance, mintAmount + amountVoltOut);
    }

    /// @notice pcv deposit receives underlying token on mint
    function testSwapUnderlyingForVolt() public {
        uint256 userStartingVoltBalance = volt.balanceOf(address(this));
        uint256 minAmountOut = psm.getMintAmountOut(mintAmount);

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
        assertApproxEq(
            endingPSMUnderlyingBalance.toInt256(),
            (mintAmount + mintAmount * 100_000).toInt256(),
            1
        ); /// allow 1 basis point of error
    }

    /// @notice pcv deposit gets depleted on redeem
    function testSwapFeiForUnderlying() public {
        uint256 startingUserUnderlyingBalance = underlyingToken.balanceOf(
            address(this)
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

        assertEq(endingPSMUnderlyingBalance, mintAmount * 100_000 - amountOut);
        assertEq(endingUserVOLTBalance, 0);
        assertEq(
            endingUserUnderlyingBalance,
            startingUserUnderlyingBalance + amountOut
        );
    }

    /// @notice redeem fails without approval
    function testSwapFeiForUnderlyingFailsWithoutApproval() public {
        vm.expectRevert(bytes("ERC20: transfer amount exceeds allowance"));

        psm.redeem(address(this), mintAmount, mintAmount);
    }

    /// @notice mint fails without approval
    function testSwapUnderlyingForFeiFailsWithoutApproval() public {
        vm.expectRevert(bytes("ERC20: transfer amount exceeds allowance"));

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

        vm.prank(feiDaiPsm);
        underlyingToken.mint(address(psm), mintAmount);

        uint256 startingBalance = underlyingToken.balanceOf(address(this));
        psm.withdrawERC20(address(underlyingToken), address(this), mintAmount);
        uint256 endingBalance = underlyingToken.balanceOf(address(this));

        assertEq(endingBalance - startingBalance, mintAmount);
    }
}
