// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Vm} from "./../unit/utils/Vm.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {CoreV2} from "../../core/CoreV2.sol";
import {ICoreV2} from "../../core/ICoreV2.sol";
import {Constants} from "../../Constants.sol";
import {IVolt, Volt} from "../../volt/Volt.sol";
import {PCVGuardian} from "../../pcv/PCVGuardian.sol";
import {PriceBoundPSM} from "../../peg/PriceBoundPSM.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {OraclePassThrough} from "../../oracle/OraclePassThrough.sol";
import {PegStabilityModule} from "../../peg/PegStabilityModule.sol";

contract IntegrationTestDaiCleanPriceBoundPSM is DSTest {
    using SafeCast for *;

    /// reference PSM to test against
    PriceBoundPSM private immutable priceBoundPsm =
        PriceBoundPSM(MainnetAddresses.VOLT_DAI_PSM);
    PriceBoundPSM private cleanPsm;

    ICoreV2 private core = ICoreV2(MainnetAddresses.CORE);
    IVolt private volt = IVolt(MainnetAddresses.VOLT);
    IERC20 private dai = IERC20(MainnetAddresses.DAI);
    IERC20 private underlyingToken = dai;

    uint256 public constant mintAmount = 10_000_000e18;
    uint256 public constant voltMintAmount = 10_000_000e18;

    OraclePassThrough public oracle =
        OraclePassThrough(MainnetAddresses.ORACLE_PASS_THROUGH);

    PCVGuardian public pcvGuardian = PCVGuardian(MainnetAddresses.PCV_GUARDIAN);

    Vm public constant vm = Vm(HEVM_ADDRESS);

    uint128 voltFloorPrice = 9_000;
    uint128 voltCeilingPrice = 10_000;

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
        cleanPsm = new PriceBoundPSM(
            voltFloorPrice,
            voltCeilingPrice,
            oracleParams,
            dai
        );

        uint256 balance = dai.balanceOf(
            MainnetAddresses.DAI_USDC_USDT_CURVE_POOL
        );
        vm.prank(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        dai.transfer(address(this), balance);

        vm.startPrank(MainnetAddresses.GOVERNOR);

        /// pull all VOLT before minting to ensure Volt balance parity on psms
        pcvGuardian.withdrawAllERC20ToSafeAddress(
            address(priceBoundPsm),
            address(volt)
        );

        /// grant governor the minter role to ensure dai balance parity on psms
        core.grantMinter(MainnetAddresses.GOVERNOR);

        /// mint VOLT to the user
        volt.mint(address(priceBoundPsm), voltMintAmount);
        volt.mint(address(cleanPsm), voltMintAmount);
        volt.mint(address(this), voltMintAmount);

        /// pull all dai
        pcvGuardian.withdrawAllToSafeAddress(address(priceBoundPsm));

        vm.stopPrank();

        dai.transfer(address(priceBoundPsm), balance / 3);
        dai.transfer(address(cleanPsm), balance / 3);
    }

    /// @notice PSM is set up correctly
    function testSetUpCorrectly() public {
        assertTrue(priceBoundPsm.doInvert());
        assertTrue(priceBoundPsm.isPriceValid());
        assertEq(priceBoundPsm.floor(), voltFloorPrice);
        assertEq(priceBoundPsm.ceiling(), voltCeilingPrice);
        assertEq(address(priceBoundPsm.oracle()), address(oracle));
        assertEq(address(priceBoundPsm.backupOracle()), address(0));
        assertEq(priceBoundPsm.decimalsNormalizer(), 0);
        assertEq(address(priceBoundPsm.underlyingToken()), address(dai));

        assertTrue(cleanPsm.doInvert());
        assertEq(address(cleanPsm.oracle()), address(oracle));
        assertEq(address(cleanPsm.backupOracle()), address(0));
        assertEq(cleanPsm.decimalsNormalizer(), 0);
        assertEq(address(cleanPsm.underlyingToken()), address(dai));
        assertEq(cleanPsm.floor(), voltFloorPrice);
        assertEq(cleanPsm.ceiling(), voltCeilingPrice);
    }

    /// @notice PSM is set up correctly and redeem view function is working
    function testGetRedeemAmountOut(uint128 amountVoltIn) public {
        uint256 currentPegPrice = oracle.getCurrentOraclePrice();

        uint256 amountOut = (amountVoltIn * currentPegPrice) / 1e18;

        assertApproxEq(
            priceBoundPsm.getRedeemAmountOut(amountVoltIn).toInt256(),
            amountOut.toInt256(),
            0
        );
        assertApproxEq(
            cleanPsm.getRedeemAmountOut(amountVoltIn).toInt256(),
            amountOut.toInt256(),
            0
        );

        assertEq(
            cleanPsm.getRedeemAmountOut(amountVoltIn),
            priceBoundPsm.getRedeemAmountOut(amountVoltIn)
        );
    }

    /// @notice PSM is set up correctly and view functions are working
    function testGetMintAmountOut(uint256 amountDaiIn) public {
        vm.assume(dai.balanceOf(address(this)) > amountDaiIn);

        uint256 currentPegPrice = oracle.getCurrentOraclePrice();

        uint256 amountOut = (amountDaiIn * 1e18) / currentPegPrice;

        assertApproxEq(
            priceBoundPsm.getMintAmountOut(amountDaiIn).toInt256(),
            amountOut.toInt256(),
            0
        );

        assertApproxEq(
            cleanPsm.getMintAmountOut(amountDaiIn).toInt256(),
            amountOut.toInt256(),
            0
        );

        assertEq(
            cleanPsm.getMintAmountOut(amountDaiIn),
            priceBoundPsm.getMintAmountOut(amountDaiIn)
        );
    }

    function testMintFuzz(uint32 amountStableIn) public {
        uint256 amountVoltOut = cleanPsm.getMintAmountOut(amountStableIn);

        uint256 amountVoltOutPriceBound = priceBoundPsm.getMintAmountOut(
            amountStableIn
        );

        uint256 startingUserVoltBalance = volt.balanceOf(address(this));
        uint256 startingCleanPsmBalance = cleanPsm.balance();

        underlyingToken.approve(address(cleanPsm), amountStableIn);
        cleanPsm.mint(address(this), amountStableIn, amountVoltOut);

        uint256 endingUserVoltBalance1 = volt.balanceOf(address(this));
        uint256 endingPSMUnderlyingBalance = underlyingToken.balanceOf(
            address(cleanPsm)
        );
        uint256 endingCleanPsmBalance = cleanPsm.balance();

        /// assert psm receives amount stable in
        assertEq(
            endingCleanPsmBalance - startingCleanPsmBalance,
            amountStableIn
        );

        uint256 startingPriceBoundPsmBalance = priceBoundPsm.balance();
        underlyingToken.approve(address(priceBoundPsm), amountStableIn);

        priceBoundPsm.mint(
            address(this),
            amountStableIn,
            amountVoltOutPriceBound
        );

        uint256 endingUserVoltBalance2 = volt.balanceOf(address(this));
        uint256 endingPSMUnderlyingBalancePriceBound = underlyingToken
            .balanceOf(address(priceBoundPsm));
        uint256 endingPriceBoundPsmBalance = priceBoundPsm.balance();

        /// assert psm receives amount stable in
        assertEq(
            endingPriceBoundPsmBalance - startingPriceBoundPsmBalance,
            amountStableIn
        );

        assertEq(
            endingUserVoltBalance1,
            startingUserVoltBalance + amountVoltOut
        );

        assertEq(
            endingPSMUnderlyingBalance,
            endingPSMUnderlyingBalancePriceBound
        );

        assertEq(
            endingUserVoltBalance2 - endingUserVoltBalance1,
            amountVoltOut
        );

        assertEq(
            endingUserVoltBalance2 - endingUserVoltBalance1,
            amountVoltOutPriceBound
        );
    }

    function testMintFuzzNotEnoughIn(uint32 amountStableIn) public {
        uint256 amountVoltOut = cleanPsm.getMintAmountOut(amountStableIn);

        uint256 amountVoltOutPriceBound = priceBoundPsm.getMintAmountOut(
            amountStableIn
        );

        underlyingToken.approve(address(cleanPsm), amountStableIn);
        vm.expectRevert("PegStabilityModule: Mint not enough out");
        cleanPsm.mint(address(this), amountStableIn, amountVoltOut + 1);

        underlyingToken.approve(address(priceBoundPsm), amountStableIn);
        vm.expectRevert("PegStabilityModule: Mint not enough out");
        priceBoundPsm.mint(
            address(this),
            amountStableIn,
            amountVoltOutPriceBound + 1
        );
    }

    function testRedeemFuzz(uint32 amountVoltIn) public {
        uint256 amountOut = cleanPsm.getRedeemAmountOut(amountVoltIn);

        uint256 underlyingOutPriceBound = priceBoundPsm.getRedeemAmountOut(
            amountVoltIn
        );

        uint256 startingUserUnderlyingBalance = underlyingToken.balanceOf(
            address(this)
        );

        uint256 startingPsmUnderlyingBalance = cleanPsm.balance();
        uint256 startingPSMVoltBalance = volt.balanceOf(address(cleanPsm));

        volt.approve(address(cleanPsm), amountVoltIn);
        cleanPsm.redeem(address(this), amountVoltIn, amountOut);

        uint256 endingUserUnderlyingBalance1 = underlyingToken.balanceOf(
            address(this)
        );
        uint256 endingPSMVoltBalance = volt.balanceOf(address(cleanPsm));
        uint256 endingPsmUnderlyingBalance = cleanPsm.balance();

        assertEq(
            startingPsmUnderlyingBalance - endingPsmUnderlyingBalance,
            underlyingOutPriceBound
        );
        assertEq(endingPSMVoltBalance - startingPSMVoltBalance, amountVoltIn);

        volt.approve(address(priceBoundPsm), amountVoltIn);

        priceBoundPsm.redeem(
            address(this),
            amountVoltIn,
            underlyingOutPriceBound
        );

        uint256 endingUserUnderlyingBalance2 = underlyingToken.balanceOf(
            address(this)
        );

        uint256 endingPSMUnderlyingBalancePriceBound = volt.balanceOf(
            address(priceBoundPsm)
        );

        assertEq(
            endingUserUnderlyingBalance1,
            startingUserUnderlyingBalance + amountOut
        );

        assertEq(endingPSMVoltBalance, endingPSMUnderlyingBalancePriceBound);

        assertEq(
            endingUserUnderlyingBalance2 - endingUserUnderlyingBalance1,
            amountOut
        );

        assertEq(
            endingUserUnderlyingBalance2 - endingUserUnderlyingBalance1,
            underlyingOutPriceBound
        );
    }

    function testRedeemFuzzNotEnoughOut(uint32 amountVoltIn) public {
        uint256 amountOut = cleanPsm.getRedeemAmountOut(amountVoltIn);

        uint256 underlyingOutPriceBound = priceBoundPsm.getRedeemAmountOut(
            amountVoltIn
        );

        volt.approve(address(cleanPsm), amountVoltIn);
        vm.expectRevert("PegStabilityModule: Redeem not enough out");
        cleanPsm.redeem(address(this), amountVoltIn, amountOut + 1);

        volt.approve(address(priceBoundPsm), amountVoltIn);
        vm.expectRevert("PegStabilityModule: Redeem not enough out");
        priceBoundPsm.redeem(
            address(this),
            amountVoltIn,
            underlyingOutPriceBound + 1
        );
    }

    /// @notice pcv deposit receives underlying token on mint
    function testSwapUnderlyingForVolt() public {
        uint256 amountStableIn = 101_000;
        uint256 amountVoltOut = cleanPsm.getMintAmountOut(amountStableIn);
        uint256 startingUserVoltBalance = volt.balanceOf(address(this));
        uint256 startingPSMUnderlyingBalance = underlyingToken.balanceOf(
            address(cleanPsm)
        );

        underlyingToken.approve(address(cleanPsm), amountStableIn);
        cleanPsm.mint(address(this), amountStableIn, amountVoltOut);

        uint256 endingUserVoltBalance = volt.balanceOf(address(this));
        uint256 endingPSMUnderlyingBalance = underlyingToken.balanceOf(
            address(cleanPsm)
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

    /// @notice redeem fails without approval
    function testSwapVoltFordaiFailsWithoutApproval() public {
        vm.expectRevert("ERC20: transfer amount exceeds allowance");

        cleanPsm.redeem(address(this), mintAmount, mintAmount);
    }

    function testMintFailsWhenMintExceedsPSMBalance() public {
        underlyingToken.approve(address(cleanPsm), type(uint256).max);

        uint256 currentPegPrice = oracle.getCurrentOraclePrice();
        uint256 psmVoltBalance = volt.balanceOf(address(cleanPsm));

        // we get the amount we want to put in by getting the total PSM balance and dividing by the current peg price
        // this lets us get the maximum amount we can deposit
        uint256 amountIn = (psmVoltBalance * currentPegPrice) / 1e6;

        // this will revert (correctly) as the math above is less precise than the PSMs, therefore our amountIn
        // will slightly exceed the balance the PSM can give to us.
        vm.expectRevert("Dai/insufficient-balance");

        cleanPsm.mint(address(this), amountIn, psmVoltBalance);
    }

    /// @notice mint fails without approval
    function testSwapUnderlyingForVoltFailsWithoutApproval() public {
        vm.expectRevert("Dai/insufficient-allowance");

        cleanPsm.mint(address(this), mintAmount, 0);
    }

    /// @notice withdraw succeeds with correct permissions
    function testWithdrawSuccess() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        core.grantPCVController(address(this));

        uint256 startingBalance = underlyingToken.balanceOf(address(this));
        cleanPsm.withdraw(address(this), mintAmount);
        uint256 endingBalance = underlyingToken.balanceOf(address(this));

        assertEq(endingBalance - startingBalance, mintAmount);
    }

    /// @notice withdraw fails without correct permissions
    function testWithdrawFailure() public {
        vm.expectRevert(bytes("CoreRef: Caller is not a PCV controller"));

        cleanPsm.withdraw(address(this), 100);
    }

    /// @notice withdraw erc20 fails without correct permissions
    function testERC20WithdrawFailure() public {
        vm.expectRevert(bytes("CoreRef: Caller is not a PCV controller"));

        cleanPsm.withdrawERC20(address(underlyingToken), address(this), 100);
    }

    function testPauseMintFailsNotGovernorGuardian() public {
        vm.expectRevert("CoreRef: Caller is not a guardian or governor");
        cleanPsm.pauseMint();
    }

    function testUnpauseMintFailsNotGovernorGuardian() public {
        vm.expectRevert("CoreRef: Caller is not a guardian or governor");
        cleanPsm.unpauseMint();
    }

    function testPauseRedeemFailsNotGovernorGuardian() public {
        vm.expectRevert("CoreRef: Caller is not a guardian or governor");
        cleanPsm.pauseRedeem();
    }

    function testUnpauseRedeemFailsNotGovernorGuardian() public {
        vm.expectRevert("CoreRef: Caller is not a guardian or governor");
        cleanPsm.unpauseRedeem();
    }

    /// @notice withdraw erc20 succeeds with correct permissions
    function testERC20WithdrawSuccess() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        core.grantPCVController(address(this));

        uint256 startingBalance = underlyingToken.balanceOf(address(this));
        cleanPsm.withdrawERC20(
            address(underlyingToken),
            address(this),
            mintAmount
        );
        uint256 endingBalance = underlyingToken.balanceOf(address(this));

        assertEq(endingBalance - startingBalance, mintAmount);
    }

    function testDepositNoOp() public {
        cleanPsm.deposit();
    }

    /// @notice deposit fails when paused
    function testDepositFailsWhenPaused() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        cleanPsm.pause();

        vm.expectRevert("Pausable: paused");
        cleanPsm.deposit();
    }

    /// @notice redeem fails when paused
    function testRedeemFailsWhenPaused() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        cleanPsm.pause();

        vm.expectRevert("Pausable: paused");
        cleanPsm.redeem(address(this), 100, 100);
    }

    /// @notice mint fails when paused
    function testMintFailsWhenPaused() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        cleanPsm.pause();

        vm.expectRevert("Pausable: paused");
        cleanPsm.mint(address(this), 100, 100);
    }
}
