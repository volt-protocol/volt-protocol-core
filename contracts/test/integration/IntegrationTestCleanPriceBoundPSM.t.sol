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
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {IOraclePassThrough} from "../../oracle/IOraclePassThrough.sol";
import {PegStabilityModule} from "../../peg/PegStabilityModule.sol";
import {IGRLM, GlobalRateLimitedMinter} from "../../limiter/GlobalRateLimitedMinter.sol";
import {TestAddresses as addresses} from "../unit/utils/TestAddresses.sol";
import {getCoreV2} from "./../unit/utils/Fixtures.sol";

import "hardhat/console.sol";

/// Differential Test that compares current production PSM to the new PSM
/// to ensure parity in behavior
contract IntegrationTestCleanPriceBoundPSM is DSTest {
    using SafeCast for *;

    /// reference PSM to test against
    PegStabilityModule private immutable priceBoundPsm =
        PegStabilityModule(MainnetAddresses.VOLT_USDC_PSM);
    PegStabilityModule private cleanPsm;

    ICoreV2 private core = ICoreV2(MainnetAddresses.CORE);
    CoreV2 private tmpCore;
    IVolt private tmpVolt;
    IVolt private volt = IVolt(MainnetAddresses.VOLT);
    IERC20 private usdc = IERC20(MainnetAddresses.USDC);
    IERC20 private underlyingToken = usdc;
    GlobalRateLimitedMinter public grlm;

    uint256 public constant mintAmount = 10_000_000e6;
    uint256 public constant voltMintAmount = 10_000_000e18;

    IOraclePassThrough public oracle =
        IOraclePassThrough(MainnetAddresses.ORACLE_PASS_THROUGH);

    PCVGuardian public pcvGuardian = PCVGuardian(MainnetAddresses.PCV_GUARDIAN);

    Vm public constant vm = Vm(HEVM_ADDRESS);

    uint128 voltFloorPrice = 1.04e6;
    uint128 voltCeilingPrice = 1.1e6;

    /// ---------- GRLM PARAMS ----------

    /// maximum rate limit per second is 100 VOLT
    uint256 public constant maxRateLimitPerSecondMinting = 100e18;

    /// replenish 500k VOLT per day
    uint128 public constant rateLimitPerSecondMinting = 5.787e18;

    /// buffer cap of 10m VOLT
    uint128 public constant bufferCapMinting = uint128(voltMintAmount);

    function setUp() public {
        tmpCore = getCoreV2();
        tmpVolt = tmpCore.volt();

        /// create PSM
        cleanPsm = new PegStabilityModule(
            address(tmpCore),
            address(oracle),
            address(0),
            -12,
            false,
            usdc,
            voltFloorPrice,
            voltCeilingPrice
        );
        vm.prank(addresses.governorAddress);
        tmpCore.grantLocker(address(cleanPsm));
        grlm = new GlobalRateLimitedMinter(
            address(tmpCore),
            maxRateLimitPerSecondMinting,
            rateLimitPerSecondMinting,
            bufferCapMinting
        );

        vm.startPrank(addresses.governorAddress);
        tmpCore.setGlobalRateLimitedMinter(IGRLM(address(grlm)));
        tmpCore.grantMinter(address(grlm));
        tmpCore.grantRateLimitedMinter(address(cleanPsm));
        tmpCore.grantRateLimitedRedeemer(address(cleanPsm));
        tmpCore.grantLocker(address(cleanPsm));
        tmpCore.grantLocker(address(grlm));
        vm.stopPrank();

        uint256 balance = usdc.balanceOf(MainnetAddresses.KRAKEN_USDC_WHALE);
        vm.prank(MainnetAddresses.KRAKEN_USDC_WHALE);
        usdc.transfer(address(this), balance);

        vm.startPrank(MainnetAddresses.GOVERNOR);

        /// pull all VOLT before minting to ensure Volt balance parity on psms
        pcvGuardian.withdrawAllERC20ToSafeAddress(
            address(priceBoundPsm),
            address(volt)
        );

        vm.label(address(tmpCore), "TMP Core");
        vm.label(address(cleanPsm), "cleanPsm");
        vm.label(address(grlm), "Global Rate Limited Minter");
        vm.label(address(tmpVolt), "TMP VOLT");

        /// grant governor the minter role to ensure USDC balance parity on psms
        core.grantMinter(MainnetAddresses.GOVERNOR);

        /// mint VOLT to the user and deprecated PSM
        volt.mint(address(priceBoundPsm), voltMintAmount);
        volt.mint(address(this), voltMintAmount);
        tmpVolt.mint(address(this), voltMintAmount);

        /// pull all USDC
        pcvGuardian.withdrawAllToSafeAddress(address(priceBoundPsm));

        vm.stopPrank();

        usdc.transfer(address(priceBoundPsm), balance / 3);
        usdc.transfer(address(cleanPsm), balance / 3);
    }

    /// @notice PSM is set up correctly
    function testSetUpCorrectly() public {
        assertTrue(priceBoundPsm.doInvert());
        assertTrue(priceBoundPsm.isPriceValid());
        assertEq(address(priceBoundPsm.oracle()), address(oracle));
        assertEq(address(priceBoundPsm.backupOracle()), address(0));
        assertEq(priceBoundPsm.decimalsNormalizer(), 12);
        assertEq(address(priceBoundPsm.underlyingToken()), address(usdc));

        assertTrue(!cleanPsm.doInvert());
        assertEq(address(cleanPsm.core()), address(tmpCore));
        assertEq(address(cleanPsm.oracle()), address(oracle));
        assertEq(address(cleanPsm.backupOracle()), address(0));
        assertEq(cleanPsm.decimalsNormalizer(), -12);
        assertEq(address(cleanPsm.underlyingToken()), address(usdc));
        assertEq(cleanPsm.floor(), voltFloorPrice);
        assertEq(cleanPsm.ceiling(), voltCeilingPrice);
    }

    /// @notice PSM is set up correctly and redeem view function is working
    function testGetRedeemAmountOut(uint128 amountVoltIn) public {
        uint256 currentPegPrice = oracle.getCurrentOraclePrice() / 1e12;

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

        /// less than 1 basis point of deviation
        assertApproxEq(
            cleanPsm.getRedeemAmountOut(amountVoltIn).toInt256(),
            priceBoundPsm.getRedeemAmountOut(amountVoltIn).toInt256(),
            0
        );
    }

    /// @notice PSM is set up correctly and redeem view function is working
    function testGetRedeemAmountOutPpq(uint128 amountVoltIn) public {
        vm.assume(amountVoltIn > 1e10); /// ensure accuracy down to the hundred thousandth

        uint256 currentPegPrice = oracle.getCurrentOraclePrice() / 1e12;

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

        if (amountOut >= 1_000_000) {
            /// accurate at least to the hundred thousandth
            assertApproxEqPpq(
                cleanPsm.getRedeemAmountOut(amountVoltIn).toInt256(),
                priceBoundPsm.getRedeemAmountOut(amountVoltIn).toInt256(),
                10_000_000_000_000
            );
        }
    }

    /// @notice PSM is set up correctly and view functions are working
    function testGetMintAmountOut(uint256 amountUSDCIn) public {
        vm.assume(usdc.balanceOf(address(this)) > amountUSDCIn);

        uint256 currentPegPrice = oracle.getCurrentOraclePrice() / 1e12;

        uint256 amountOut = (((amountUSDCIn * 1e18) / currentPegPrice));

        assertApproxEq(
            priceBoundPsm.getMintAmountOut(amountUSDCIn).toInt256(),
            amountOut.toInt256(),
            0
        );

        assertApproxEq(
            cleanPsm.getMintAmountOut(amountUSDCIn).toInt256(),
            amountOut.toInt256(),
            0
        );

        /// allow one millionth deviation
        assertApproxEqPpq(
            cleanPsm.getMintAmountOut(amountUSDCIn).toInt256(),
            priceBoundPsm.getMintAmountOut(amountUSDCIn).toInt256(),
            1_000_000_000_000
        );
    }

    function testMintFuzz(uint32 amountStableIn) public {
        uint256 amountVoltOut = cleanPsm.getMintAmountOut(amountStableIn);

        uint256 amountVoltOutPriceBound = priceBoundPsm.getMintAmountOut(
            amountStableIn
        );

        uint256 startingVoltTotalSupply = tmpVolt.totalSupply();
        uint256 startingUserVoltBalance = tmpVolt.balanceOf(address(this));
        uint256 startingCleanPsmBalance = cleanPsm.balance();

        underlyingToken.approve(address(cleanPsm), amountStableIn);
        cleanPsm.mint(address(this), amountStableIn, amountVoltOut);

        uint256 endingVoltTotalSupply = tmpVolt.totalSupply();
        uint256 endingUserVoltBalance1 = tmpVolt.balanceOf(address(this));
        uint256 endingPSMUnderlyingBalance = underlyingToken.balanceOf(
            address(cleanPsm)
        );
        uint256 endingCleanPsmBalance = cleanPsm.balance();

        assertEq(
            startingVoltTotalSupply + amountVoltOut,
            endingVoltTotalSupply
        );

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

        assertEq(endingUserVoltBalance1 - voltMintAmount, amountVoltOut);

        assertEq(
            endingUserVoltBalance2 - voltMintAmount,
            amountVoltOutPriceBound
        );

        assertApproxEq(
            amountVoltOutPriceBound.toInt256(),
            amountVoltOut.toInt256(),
            0
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
        uint256 startingUserVoltBalance = tmpVolt.balanceOf(address(this));

        tmpVolt.approve(address(cleanPsm), amountVoltIn);
        cleanPsm.redeem(address(this), amountVoltIn, amountOut);

        uint256 endingUserUnderlyingBalance1 = underlyingToken.balanceOf(
            address(this)
        );
        uint256 endingUserVoltBalance = tmpVolt.balanceOf(address(this));
        uint256 endingPsmUnderlyingBalance = cleanPsm.balance();

        assertEq(
            startingPsmUnderlyingBalance - endingPsmUnderlyingBalance,
            amountOut
        );
        assertEq(startingUserVoltBalance - endingUserVoltBalance, amountVoltIn);

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
        assertEq(
            amountVoltIn,
            endingPSMUnderlyingBalancePriceBound - voltMintAmount
        );
        assertEq(
            endingUserUnderlyingBalance2 - endingUserUnderlyingBalance1,
            underlyingOutPriceBound
        );
        assertApproxEq(
            underlyingOutPriceBound.toInt256(),
            amountOut.toInt256(),
            0
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

    function testSwapUnderlyingForVolt() public {
        uint256 amountStableIn = 101_000;
        uint256 amountVoltOut = cleanPsm.getMintAmountOut(amountStableIn);
        uint256 startingUserVoltBalance = tmpVolt.balanceOf(address(this));
        uint256 startingPSMUnderlyingBalance = underlyingToken.balanceOf(
            address(cleanPsm)
        );

        underlyingToken.approve(address(cleanPsm), amountStableIn);
        cleanPsm.mint(address(this), amountStableIn, amountVoltOut);

        uint256 endingUserVoltBalance = tmpVolt.balanceOf(address(this));
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
    function testSwapVoltForUSDCFailsWithoutApproval() public {
        vm.expectRevert("ERC20: insufficient allowance"); /// mock volt failure message

        cleanPsm.redeem(address(this), mintAmount, mintAmount / 1e12);
    }

    function testMintFailsWhenMintExceedsBuffer() public {
        underlyingToken.approve(address(cleanPsm), type(uint256).max);

        uint256 currentPegPrice = oracle.getCurrentOraclePrice();
        uint256 psmVoltBalance = grlm.buffer() + 1; /// try to mint 1 wei over buffer which causes failure

        /// we get the amount we want to put in by getting the
        /// total PSM balance and dividing by the current peg price
        /// this lets us get the maximum amount we can deposit
        uint256 amountIn = (psmVoltBalance * currentPegPrice) / 1e6;

        // this will revert (correctly) as the math above is less precise than the PSMs, therefore our amountIn
        // will slightly exceed the balance the PSM can give to us.
        vm.expectRevert("RateLimited: rate limit hit");

        cleanPsm.mint(address(this), amountIn, psmVoltBalance);
    }

    /// @notice mint fails without approval
    function testSwapUnderlyingForVoltFailsWithoutApproval() public {
        vm.expectRevert(bytes("ERC20: transfer amount exceeds allowance"));

        cleanPsm.mint(address(this), mintAmount, 0);
    }

    /// @notice withdraw succeeds with correct permissions
    function testWithdrawSuccess() public {
        vm.prank(address(grlm));
        tmpCore.lock(1);

        vm.prank(addresses.governorAddress);
        tmpCore.grantPCVController(address(this));

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

    /// @notice withdraw erc20 succeeds with correct permissions
    function testERC20WithdrawSuccess() public {
        vm.prank(addresses.governorAddress);
        tmpCore.grantPCVController(address(this));

        uint256 startingBalance = underlyingToken.balanceOf(address(this));
        cleanPsm.withdrawERC20(
            address(underlyingToken),
            address(this),
            mintAmount
        );
        uint256 endingBalance = underlyingToken.balanceOf(address(this));

        assertEq(endingBalance - startingBalance, mintAmount);
    }

    /// TODO add these tests

    /// @notice redeem fails when paused
    function testRedeemFailsWithoutGlobalStateRole() public {}

    /// @notice mint fails when paused
    function testMintFailsWithoutGlobalStateRole() public {}
}
