// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Vm} from "./../../unit/utils/Vm.sol";
import {Test} from "../../../../forge-std/src/Test.sol";
import {DSTest} from "./../../unit/utils/DSTest.sol";
import {CoreV2} from "../../../core/CoreV2.sol";
import {ICoreV2} from "../../../core/ICoreV2.sol";
import {Constants} from "../../../Constants.sol";
import {MockERC20} from "../../../mock/MockERC20.sol";
import {IVolt, Volt} from "../../../volt/Volt.sol";
import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";
import {NonCustodialPSM} from "../../../peg/NonCustodialPSM.sol";
import {OraclePassThrough} from "../../../oracle/OraclePassThrough.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";
import {IGRLM, GlobalRateLimitedMinter} from "../../../minter/GlobalRateLimitedMinter.sol";
import {getCoreV2, getAddresses, VoltTestAddresses} from "./../../unit/utils/Fixtures.sol";

/// Differential Test that compares current production PSM to the new PSM
/// to ensure parity in behavior
/// TODO use vm.deal to increase balance in DAI and VOLT,
/// increase values for fuzzer for more realistic tests
contract UnitTestPegStabilityModule is Test {
    using SafeCast for *;

    VoltTestAddresses public addresses = getAddresses();

    /// @notice non custodial PSM to test redemptions against
    NonCustodialPSM private priceBoundPsm;
    PegStabilityModule private cleanPsm;

    ICoreV2 private core;
    IVolt private volt;
    IERC20 private underlyingToken;
    GlobalRateLimitedMinter public grlm;

    uint256 public constant mintAmount = 10_000_000e18;
    uint256 public constant voltMintAmount = 10_000_000e18;

    OraclePassThrough public oracle;

    uint128 voltFloorPrice = 1.04e18;
    uint128 voltCeilingPrice = 1.1e18;

    /// ---------- GRLM PARAMS ----------

    /// maximum rate limit per second is 100 VOLT
    uint256 public constant maxRateLimitPerSecondMinting = 100e18;

    /// replenish 500k VOLT per day
    uint128 public constant rateLimitPerSecondMinting = 5.787e18;

    /// buffer cap of 10m VOLT
    uint128 public constant bufferCapMinting = uint128(voltMintAmount);

    function setUp() public {
        core = getCoreV2();
        volt = core.volt();

        /// create PSM
        cleanPsm = new PegStabilityModule(
            address(core),
            address(oracle),
            address(0),
            0,
            false,
            underlyingToken,
            voltFloorPrice,
            voltCeilingPrice
        );
        vm.prank(addresses.governorAddress);
        core.grantGlobalLocker(address(cleanPsm));
        grlm = new GlobalRateLimitedMinter(
            address(core),
            maxRateLimitPerSecondMinting,
            rateLimitPerSecondMinting,
            bufferCapMinting
        );

        vm.startPrank(addresses.governorAddress);
        core.setGlobalRateLimitedMinter(IGRLM(address(grlm)));
        core.grantMinter(address(grlm));
        core.grantRateLimitedMinter(address(cleanPsm));
        core.grantGlobalLocker(address(cleanPsm));
        vm.stopPrank();

        vm.label(address(cleanPsm), "New PSM");
        vm.label(address(priceBoundPsm), "Existing PSM");

        /// mint VOLT to the user
        volt.mint(address(priceBoundPsm), voltMintAmount);
        volt.mint(address(this), voltMintAmount);
        volt.mint(address(this), voltMintAmount);

        vm.stopPrank();

        deal(address(underlyingToken), address(priceBoundPsm), mintAmount);
        deal(address(underlyingToken), address(cleanPsm), mintAmount);
    }

    /// @notice PSM is set up correctly
    function testSetUpCorrectly() public {
        assertTrue(priceBoundPsm.doInvert());
        assertTrue(priceBoundPsm.isPriceValid());
        assertEq(address(priceBoundPsm.oracle()), address(oracle));
        assertEq(address(priceBoundPsm.backupOracle()), address(0));
        assertEq(priceBoundPsm.decimalsNormalizer(), 0);
        assertEq(
            address(priceBoundPsm.underlyingToken()),
            address(underlyingToken)
        );

        assertTrue(!cleanPsm.doInvert());
        assertEq(address(cleanPsm.oracle()), address(oracle));
        assertEq(address(cleanPsm.backupOracle()), address(0));
        assertEq(cleanPsm.decimalsNormalizer(), 0);
        assertEq(address(cleanPsm.underlyingToken()), address(underlyingToken));
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

        assertApproxEq(
            cleanPsm.getRedeemAmountOut(amountVoltIn).toInt256(),
            priceBoundPsm.getRedeemAmountOut(amountVoltIn).toInt256(),
            0
        );
    }

    /// @notice PSM is set up correctly and redeem view function is working
    function testGetRedeemAmountOutPpq(uint128 amountVoltIn) public {
        vm.assume(amountVoltIn > 1e8);

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

        assertApproxEqPpq(
            cleanPsm.getRedeemAmountOut(amountVoltIn).toInt256(),
            priceBoundPsm.getRedeemAmountOut(amountVoltIn).toInt256(),
            1_000_000_000
        );
    }

    /// @notice PSM is set up correctly and view functions are working
    function testGetMintAmountOut(uint128 amountDaiIn) public {
        uint256 currentPegPrice = oracle.getCurrentOraclePrice();

        uint256 amountOut = (uint256(amountDaiIn) * 1e18) / currentPegPrice;

        assertApproxEq(
            cleanPsm.getMintAmountOut(amountDaiIn).toInt256(),
            amountOut.toInt256(),
            0
        );
    }

    /// @notice PSM is set up correctly and view functions are working
    function testGetMintAmountOutPpq(uint128 amountDaiIn) public {
        vm.assume(amountDaiIn > 1e8);
        uint256 currentPegPrice = oracle.getCurrentOraclePrice();

        uint256 amountOut = (uint256(amountDaiIn) * 1e18) / currentPegPrice;

        assertApproxEq(
            cleanPsm.getMintAmountOut(amountDaiIn).toInt256(),
            amountOut.toInt256(),
            0
        );
    }

    function testMintFuzz(uint32 amountStableIn) public {
        uint256 amountVoltOut = cleanPsm.getMintAmountOut(amountStableIn);

        uint256 startingVoltTotalSupply = volt.totalSupply();
        uint256 startingUserVoltBalance = volt.balanceOf(address(this));
        uint256 startingCleanPsmBalance = cleanPsm.balance();

        underlyingToken.approve(address(cleanPsm), amountStableIn);
        cleanPsm.mint(address(this), amountStableIn, amountVoltOut);

        uint256 endingVoltTotalSupply = volt.totalSupply();
        uint256 endingUserVoltBalance1 = volt.balanceOf(address(this));
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
    }

    function testMintFuzzNotEnoughIn(uint32 amountStableIn) public {
        uint256 amountVoltOut = cleanPsm.getMintAmountOut(amountStableIn);

        underlyingToken.approve(address(cleanPsm), amountStableIn);
        vm.expectRevert("PegStabilityModule: Mint not enough out");
        cleanPsm.mint(address(this), amountStableIn, amountVoltOut + 1);
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
        uint256 startingUserVoltBalance = volt.balanceOf(address(this));

        volt.approve(address(cleanPsm), amountVoltIn);
        cleanPsm.redeem(address(this), amountVoltIn, amountOut);

        uint256 endingUserUnderlyingBalance1 = underlyingToken.balanceOf(
            address(this)
        );
        uint256 endingUserVoltBalance = volt.balanceOf(address(this));
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
    function testSwapVoltForunderlyingTokenFailsWithoutApproval() public {
        vm.expectRevert("ERC20: insufficient allowance");

        cleanPsm.redeem(address(this), mintAmount, mintAmount);
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
        vm.expectRevert("Dai/insufficient-allowance");

        cleanPsm.mint(address(this), mintAmount, 0);
    }

    /// @notice withdraw succeeds with correct permissions
    function testWithdrawSuccess() public {
        vm.prank(addresses.governorAddress);
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

    /// @notice withdraw erc20 succeeds with correct permissions
    function testERC20WithdrawSuccess() public {
        vm.prank(addresses.governorAddress);
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
        vm.prank(addresses.governorAddress);
        cleanPsm.pause();

        vm.expectRevert("Pausable: paused");
        cleanPsm.deposit();
    }
}