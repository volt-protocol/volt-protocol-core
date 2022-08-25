// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {MockPCVDepositV2} from "../../mock/MockPCVDepositV2.sol";
import {IPCVDeposit} from "../../pcv/IPCVDeposit.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {OraclePassThrough} from "../../oracle/OraclePassThrough.sol";
import {ICore} from "../../core/ICore.sol";
import {Core} from "../../core/Core.sol";
import {IVolt, Volt} from "../../volt/Volt.sol";
import {PriceBoundPSM, PegStabilityModule} from "../../peg/PriceBoundPSM.sol";
import {getCore, getMainnetAddresses, VoltTestAddresses} from "../unit/utils/Fixtures.sol";
import {CompoundPCVDepositV2} from "../../pcv/compound/CompoundPCVDepositV2.sol";
import {Vm} from "./../unit/utils/Vm.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";

import {Constants} from "../../Constants.sol";

contract IntegrationTestPriceBoundPSMTest is DSTest {
    using SafeCast for *;
    PriceBoundPSM private psm;
    ICore private core = ICore(MainnetAddresses.CORE);
    ICore private feiCore = ICore(MainnetAddresses.FEI_CORE);
    IVolt private volt = IVolt(MainnetAddresses.VOLT);
    IVolt private fei = IVolt(MainnetAddresses.FEI);
    IVolt private underlyingToken = fei;

    /// ------------ Minting and RateLimited System Params ------------

    uint256 public constant mintAmount = 10_000_000e18;
    uint256 public constant bufferCap = 10_000_000e18;
    uint256 public constant individualMaxBufferCap = 5_000_000e18;
    uint256 public constant rps = 10_000e18;

    /// ------------ Oracle System Params ------------

    /// @notice prices during test will increase 1% monthly
    int256 public constant monthlyChangeRateBasisPoints = 100;
    uint256 public constant maxDeviationThresholdBasisPoints = 1_000;

    /// @notice chainlink job id on mainnet
    bytes32 public immutable jobId =
        0x3666376662346162636564623438356162323765623762623339636166383237;
    /// @notice chainlink oracle address on mainnet
    address public immutable oracleAddress =
        MainnetAddresses.CHAINLINK_ORACLE_ADDRESS;

    /// @notice live FEI PCV Deposit
    CompoundPCVDepositV2 public immutable rariVoltPCVDeposit =
        CompoundPCVDepositV2(MainnetAddresses.RARI_VOLT_PCV_DEPOSIT);

    /// @notice fei DAO timelock address
    address public immutable feiDAOTimelock = MainnetAddresses.FEI_DAO_TIMELOCK;

    /// @notice Oracle Pass Through contract
    OraclePassThrough public oracle =
        OraclePassThrough(MainnetAddresses.DEPRECATED_ORACLE_PASS_THROUGH);

    Vm public constant vm = Vm(HEVM_ADDRESS);

    uint256 voltFloorPrice = 9_000; /// 1 volt for .9 fei is the max allowable price
    uint256 voltCeilingPrice = 10_000; /// 1 volt for 1 fei is the minimum price

    function setUp() public {
        PegStabilityModule.OracleParams memory oracleParams;

        oracleParams = PegStabilityModule.OracleParams({
            coreAddress: address(core),
            oracleAddress: address(oracle),
            backupOracle: address(0),
            decimalsNormalizer: 0,
            doInvert: true
        });

        /// create PSM
        psm = new PriceBoundPSM(
            voltFloorPrice,
            voltCeilingPrice,
            oracleParams,
            30,
            0,
            10_000_000_000e18,
            10_000e18,
            10_000_000e18,
            IERC20(address(fei)),
            IPCVDeposit(rariVoltPCVDeposit)
        );

        vm.prank(feiDAOTimelock);
        fei.mint(address(this), mintAmount);

        vm.startPrank(MainnetAddresses.GOVERNOR);

        /// grant the PSM the PCV Controller role
        core.grantMinter(MainnetAddresses.GOVERNOR);
        /// mint VOLT to the user
        volt.mint(address(psm), mintAmount);
        volt.mint(address(this), mintAmount);
        vm.stopPrank();

        vm.prank(MainnetAddresses.FEI_GOVERNOR);
        fei.mint(address(psm), mintAmount * 100_000);
    }

    /// @notice PSM inverts price
    function testDoInvert() public {
        assertTrue(psm.doInvert());
    }

    /// @notice PSM is set up correctly and view functions are working
    function testGetRedeemAmountOut() public {
        uint256 currentPegPrice = oracle.getCurrentOraclePrice();
        uint256 fee = (mintAmount * psm.redeemFeeBasisPoints()) /
            Constants.BASIS_POINTS_GRANULARITY;

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
        assertEq(psm.getMaxMintAmountOut(), bufferCap + startingBalance);

        vm.startPrank(MainnetAddresses.GOVERNOR);
        volt.mint(address(psm), mintAmount);
        vm.stopPrank();

        assertEq(
            psm.getMaxMintAmountOut(),
            bufferCap + mintAmount + startingBalance
        );
    }

    /// @notice PSM is set up correctly and view functions are working
    function testGetMintAmountOut() public {
        uint256 currentPegPrice = oracle.getCurrentOraclePrice();

        uint256 fee = (mintAmount * psm.mintFeeBasisPoints()) /
            Constants.BASIS_POINTS_GRANULARITY;

        uint256 amountOut = (((mintAmount * 1e18) / currentPegPrice)) - fee;

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

        vm.prank(MainnetAddresses.FEI_GOVERNOR);
        underlyingToken.mint(address(psm), mintAmount);

        uint256 startingBalance = underlyingToken.balanceOf(address(this));
        psm.withdrawERC20(address(underlyingToken), address(this), mintAmount);
        uint256 endingBalance = underlyingToken.balanceOf(address(this));

        assertEq(endingBalance - startingBalance, mintAmount);
    }

    /// @notice set global rate limited minter fails when caller is governor and new address is 0
    function testSetPCVDepositFailureZeroAddress() public {
        vm.startPrank(MainnetAddresses.GOVERNOR);

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
        vm.startPrank(MainnetAddresses.GOVERNOR);

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
        vm.prank(MainnetAddresses.GOVERNOR);
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
        vm.prank(MainnetAddresses.GOVERNOR);
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
