// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {MockPCVDepositV2} from "../../mock/MockPCVDepositV2.sol";
import {IPCVDeposit} from "../../pcv/IPCVDeposit.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {OraclePassThrough} from "../../oracle/OraclePassThrough.sol";
import {ScalingPriceOracle} from "../../oracle/ScalingPriceOracle.sol";
import {MockScalingPriceOracle} from "../../mock/MockScalingPriceOracle.sol";
import {ICore} from "../../core/ICore.sol";
import {Core} from "../../core/Core.sol";
import {IVolt, Volt} from "../../volt/Volt.sol";
import {PriceBoundPSM, PegStabilityModule} from "../../peg/PriceBoundPSM.sol";
import {getCore, getMainnetAddresses, FeiTestAddresses} from "../unit/utils/Fixtures.sol";
import {ERC20CompoundPCVDeposit} from "../../pcv/compound/ERC20CompoundPCVDeposit.sol";
import {Vm} from "./../unit/utils/Vm.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {Decimal} from "../../external/Decimal.sol";
import {Constants} from "../../Constants.sol";

contract IntegrationTestPriceBoundPSMUSDCTest is DSTest {
    using SafeCast for *;
    using SafeMath for uint256;
    using Decimal for Decimal.D256;
    PriceBoundPSM private psm;
    ICore private core = ICore(0xEC7AD284f7Ad256b64c6E69b84Eb0F48f42e8196);
    IVolt private volt = IVolt(0x559eBC30b0E58a45Cc9fF573f77EF1e5eb1b3E18);
    IERC20 private usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private underlyingToken = usdc;

    address public makerUSDCPSM = 0xAe2D4617c862309A3d75A0fFB358c7a5009c673F;

    /// ------------ Minting and RateLimited System Params ------------

    uint256 public constant mintAmount = 10_000_000e6;
    uint256 public constant voltMintAmount = 10_000_000e18;

    uint256 public constant bufferCap = 10_000_000e18;
    uint256 public constant individualMaxBufferCap = 5_000_000e18;
    uint256 public constant rps = 10_000e18;

    /// @notice live FEI PCV Deposit
    ERC20CompoundPCVDeposit public immutable rariVoltPCVDeposit =
        ERC20CompoundPCVDeposit(0xFeBDf448C8484834bb399d930d7E1bdC773E23bA);

    /// @notice Oracle Pass Through contract
    OraclePassThrough public oracle =
        OraclePassThrough(0x84dc71500D504163A87756dB6368CC8bB654592f);

    Vm public constant vm = Vm(HEVM_ADDRESS);
    FeiTestAddresses public addresses = getMainnetAddresses();

    /// these are inverted
    uint256 voltFloorPrice = 9_000e12; /// 1 volt for .9 usdc is the max allowable price
    uint256 voltCeilingPrice = 10_000e12; /// 1 volt for 1 usdc is the minimum price
    uint256 reservesThreshold = type(uint256).max; /// max uint so that surplus can never be allocated into the pcv deposit

    function setUp() public {
        PegStabilityModule.OracleParams memory oracleParams;

        oracleParams = PegStabilityModule.OracleParams({
            coreAddress: address(core),
            oracleAddress: address(oracle),
            backupOracle: address(0),
            decimalsNormalizer: 12,
            doInvert: true
        });

        /// create PSM
        psm = new PriceBoundPSM(
            voltFloorPrice,
            voltCeilingPrice,
            oracleParams,
            30,
            0,
            reservesThreshold,
            10_000e18,
            10_000_000e18,
            IERC20(address(usdc)),
            rariVoltPCVDeposit
        );

        uint256 balance = usdc.balanceOf(makerUSDCPSM);
        vm.prank(makerUSDCPSM);
        usdc.transfer(address(this), balance);

        vm.startPrank(addresses.voltGovernorAddress);

        /// grant the PSM the PCV Controller role
        core.grantMinter(addresses.voltGovernorAddress);
        /// mint VOLT to the user
        volt.mint(address(psm), voltMintAmount);
        volt.mint(address(this), voltMintAmount);
        vm.stopPrank();

        usdc.transfer(address(psm), balance / 2);
    }

    /// @notice PSM is set up correctly
    function testSetUpCorrectly() public {
        assertTrue(psm.doInvert());
        assertTrue(psm.isPriceValid());
        assertEq(psm.floor(), voltFloorPrice);
        assertEq(psm.ceiling(), voltCeilingPrice);
        assertEq(address(psm.oracle()), address(oracle));
        assertEq(address(psm.backupOracle()), address(0));
        assertEq(psm.decimalsNormalizer(), 12);
        assertEq(psm.mintFeeBasisPoints(), 30); /// mint costs 30 bps
        assertEq(psm.redeemFeeBasisPoints(), 0); /// redeem has no fee
        assertEq(address(psm.underlyingToken()), address(usdc));
        assertEq(psm.reservesThreshold(), reservesThreshold);
    }

    /// @notice PSM is set up correctly and redeem view function is working
    function testGetRedeemAmountOut() public {
        uint256 amountVoltIn = 100e18;

        uint256 currentPegPrice = oracle.getCurrentOraclePrice().div(1e12);
        uint256 fee = (amountVoltIn * psm.redeemFeeBasisPoints()) /
            Constants.BASIS_POINTS_GRANULARITY;

        uint256 amountOut = ((amountVoltIn * currentPegPrice).div(1e18)) - fee;

        assertApproxEq(
            psm.getRedeemAmountOut(amountVoltIn).toInt256(),
            amountOut.toInt256(),
            1
        );
    }

    /// @notice PSM is set up correctly and view functions are working
    function testGetMaxMintAmountOut() public {
        uint256 startingBalance = volt.balanceOf(address(psm));
        assertEq(psm.getMaxMintAmountOut(), bufferCap + startingBalance);

        vm.startPrank(addresses.voltGovernorAddress);
        volt.mint(address(psm), mintAmount);
        vm.stopPrank();

        assertEq(
            psm.getMaxMintAmountOut(),
            bufferCap + mintAmount + startingBalance
        );
    }

    /// @notice PSM is set up correctly and view functions are working
    function testGetMintAmountOut() public {
        uint256 amountUSDCIn = 100e18;

        uint256 currentPegPrice = oracle.getCurrentOraclePrice();

        uint256 fee = (amountUSDCIn.mul(1e12) * psm.mintFeeBasisPoints()) /
            Constants.BASIS_POINTS_GRANULARITY;

        uint256 amountOut = ((amountUSDCIn.mul(1e18) / currentPegPrice)).mul(
            1e12
        ) - fee;

        assertApproxEq(
            psm.getMintAmountOut(amountUSDCIn).toInt256(),
            amountOut.toInt256(),
            1
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
            endingUserVoltBalance,
            startingUserVoltBalance + amountVoltOut
        );
        assertEq(
            startingPSMUnderlyingBalance + amountStableIn,
            endingPSMUnderlyingBalance
        );
    }

    /// @notice pcv deposit gets depleted on redeem
    function testSwapVoltForUSDC() public {
        uint256 startingUserUnderlyingBalance = underlyingToken.balanceOf(
            address(this)
        );
        uint256 startingPSMUnderlyingBalance = underlyingToken.balanceOf(
            address(psm)
        );
        uint256 redeemAmountOut = psm.getRedeemAmountOut(mintAmount);
        uint256 startingUserVOLTBalance = volt.balanceOf(address(this));

        volt.approve(address(psm), mintAmount);
        uint256 amountOut = psm.redeem(
            address(this),
            mintAmount,
            redeemAmountOut
        );

        uint256 endingUserVOLTBalance = volt.balanceOf(address(this));
        uint256 endingUserUnderlyingBalance = underlyingToken.balanceOf(
            address(this)
        );
        uint256 endingPSMUnderlyingBalance = underlyingToken.balanceOf(
            address(psm)
        );

        assertEq(startingUserVOLTBalance, endingUserVOLTBalance + mintAmount);
        assertEq(
            endingUserUnderlyingBalance,
            startingUserUnderlyingBalance + amountOut
        );
        assertEq(
            endingPSMUnderlyingBalance,
            startingPSMUnderlyingBalance - amountOut
        );
    }

    /// @notice redeem fails without approval
    function testSwapVoltForUSDCFailsWithoutApproval() public {
        vm.expectRevert(bytes("ERC20: transfer amount exceeds allowance"));

        psm.redeem(address(this), mintAmount, mintAmount / 1e12);
    }

    /// @notice mint fails without approval
    function testSwapUnderlyingForVoltFailsWithoutApproval() public {
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
        vm.prank(addresses.voltGovernorAddress);
        core.grantPCVController(address(this));

        uint256 startingBalance = underlyingToken.balanceOf(address(this));
        psm.withdrawERC20(address(underlyingToken), address(this), mintAmount);
        uint256 endingBalance = underlyingToken.balanceOf(address(this));

        assertEq(endingBalance - startingBalance, mintAmount);
    }

    /// @notice set global rate limited minter fails when caller is governor and new address is 0
    function testSetPCVDepositFailureZeroAddress() public {
        vm.startPrank(addresses.voltGovernorAddress);

        vm.expectRevert(
            bytes("PegStabilityModule: Invalid new surplus target")
        );
        psm.setSurplusTarget(IPCVDeposit(address(0)));

        vm.stopPrank();
    }

    /// @notice set PCV deposit fails when caller is governor and new address is 0
    function testSetPCVDepositFailureNonGovernor() public {
        vm.expectRevert(
            bytes("CoreRef: Caller is not a governor or contract admin")
        );
        psm.setSurplusTarget(IPCVDeposit(address(0)));
    }

    /// @notice set PCV Deposit succeeds when caller is governor and underlying tokens match
    function testSetPCVDepositSuccess() public {
        vm.startPrank(addresses.voltGovernorAddress);

        MockPCVDepositV2 newPCVDeposit = new MockPCVDepositV2(
            address(core),
            address(underlyingToken),
            0,
            0
        );

        psm.setSurplusTarget(IPCVDeposit(address(newPCVDeposit)));

        vm.stopPrank();

        assertEq(address(newPCVDeposit), address(psm.surplusTarget()));
    }

    /// @notice set mint fee succeeds
    function testSetMintFeeSuccess() public {
        vm.prank(addresses.voltGovernorAddress);
        psm.setMintFee(100);

        assertEq(psm.mintFeeBasisPoints(), 100);
    }

    /// @notice set mint fee fails unauthorized
    function testSetMintFeeFailsWithoutCorrectRoles() public {
        vm.expectRevert(
            bytes("CoreRef: Caller is not a governor or contract admin")
        );

        psm.setMintFee(100);
    }

    /// @notice set redeem fee succeeds
    function testSetRedeemFeeSuccess() public {
        vm.prank(addresses.voltGovernorAddress);
        psm.setRedeemFee(100);

        assertEq(psm.redeemFeeBasisPoints(), 100);
    }

    /// @notice set redeem fee fails unauthorized
    function testSetRedeemFeeFailsWithoutCorrectRoles() public {
        vm.expectRevert(
            bytes("CoreRef: Caller is not a governor or contract admin")
        );

        psm.setRedeemFee(100);
    }

    /// @notice redeem fails when paused
    function testRedeemFailsWhenPaused() public {
        vm.prank(addresses.voltGovernorAddress);
        psm.pauseRedeem();

        vm.expectRevert(bytes("PegStabilityModule: Redeem paused"));
        psm.redeem(address(this), 100, 100);
    }

    /// @notice mint fails when paused
    function testMintFailsWhenPaused() public {
        vm.prank(addresses.voltGovernorAddress);
        psm.pauseMint();

        vm.expectRevert(bytes("PegStabilityModule: Minting paused"));
        psm.mint(address(this), 100, 100);
    }
}
