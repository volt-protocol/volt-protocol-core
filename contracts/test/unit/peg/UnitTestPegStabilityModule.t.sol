// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Vm} from "./../../unit/utils/Vm.sol";
import {DSTest} from "./../../unit/utils/DSTest.sol";
import {CoreV2} from "../../../core/CoreV2.sol";
import {ICoreV2} from "../../../core/ICoreV2.sol";
import {Constants} from "../../../Constants.sol";
import {MockERC20} from "../../../mock/MockERC20.sol";
import {IVolt, Volt} from "../../../volt/Volt.sol";
import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";
import {Test, console2} from "../../../../forge-std/src/Test.sol";
import {NonCustodialPSM} from "../../../peg/NonCustodialPSM.sol";
import {VoltSystemOracle} from "../../../oracle/VoltSystemOracle.sol";
import {OraclePassThrough} from "../../../oracle/OraclePassThrough.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";
import {IGRLM, GlobalRateLimitedMinter} from "../../../minter/GlobalRateLimitedMinter.sol";
import {getCoreV2, getAddresses, getLocalOracleSystem, VoltTestAddresses} from "./../../unit/utils/Fixtures.sol";

/// Differential Test that compares current production PSM to the new PSM
/// to ensure parity in behavior
/// TODO use vm.deal to increase balance in DAI and VOLT,
/// increase values for fuzzer for more realistic tests
/// TODO make it work
contract UnitTestPegStabilityModule is Test {
    using SafeCast for *;
    VoltTestAddresses public addresses = getAddresses();
    /// @notice non custodial PSM to test redemptions against
    PegStabilityModule private psm;

    ICoreV2 private core;
    IVolt private volt;
    IERC20 private underlyingToken;
    GlobalRateLimitedMinter public grlm;
    uint256 public constant mintAmount = 10_000_000e18;
    uint256 public constant voltMintAmount = 10_000_000e18;
    OraclePassThrough public oraclePassThrough;
    VoltSystemOracle public oracle;

    /// ---------- PRICE PARAMS ----------

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
        underlyingToken = IERC20(address(new MockERC20()));
        core = getCoreV2();
        volt = core.volt();
        (oracle, oraclePassThrough) = getLocalOracleSystem(voltFloorPrice);

        /// create PSM
        psm = new PegStabilityModule(
            address(core),
            address(oraclePassThrough),
            address(0),
            0,
            false,
            underlyingToken,
            voltFloorPrice,
            voltCeilingPrice
        );

        vm.prank(addresses.governorAddress);
        core.grantLevelOneLocker(address(psm));
        grlm = new GlobalRateLimitedMinter(
            address(core),
            maxRateLimitPerSecondMinting,
            rateLimitPerSecondMinting,
            bufferCapMinting
        );
        vm.startPrank(addresses.governorAddress);
        core.setGlobalRateLimitedMinter(IGRLM(address(grlm)));
        core.grantMinter(address(grlm));
        core.grantRateLimitedRedeemer(address(psm));
        core.grantRateLimitedMinter(address(psm));
        core.grantLevelOneLocker(address(psm));
        core.grantLevelTwoLocker(address(grlm));
        vm.stopPrank();

        vm.label(address(psm), "PSM");
        vm.label(address(grlm), "GRLM");
        vm.label(address(core), "CORE");

        /// mint VOLT to the user
        volt.mint(address(this), voltMintAmount);

        deal(address(underlyingToken), address(psm), mintAmount);
        deal(address(underlyingToken), address(this), mintAmount);
    }

    /// @notice PSM is set up correctly
    function testSetUpCorrectly() public {
        assertTrue(!psm.doInvert());
        assertEq(address(psm.oracle()), address(oraclePassThrough));
        assertEq(address(psm.backupOracle()), address(0));
        assertEq(psm.decimalsNormalizer(), 0);
        assertEq(address(psm.underlyingToken()), address(underlyingToken));
        assertEq(psm.floor(), voltFloorPrice);
        assertEq(psm.ceiling(), voltCeilingPrice);
    }

    /// @notice PSM is set up correctly and redeem view function is working
    function testGetRedeemAmountOut(uint128 amountVoltIn) public {
        uint256 currentPegPrice = oracle.getCurrentOraclePrice();
        uint256 amountOut = (amountVoltIn * currentPegPrice) / 1e18;

        assertApproxEq(
            psm.getRedeemAmountOut(amountVoltIn).toInt256(),
            amountOut.toInt256(),
            0
        );
    }

    /// @notice PSM is set up correctly and redeem view function is working
    function testGetRedeemAmountOutPpq(uint128 amountVoltIn) public {
        vm.assume(amountVoltIn > 1e8);
        uint256 currentPegPrice = oracle.getCurrentOraclePrice();
        uint256 amountOut = (amountVoltIn * currentPegPrice) / 1e18;

        assertApproxEq(
            psm.getRedeemAmountOut(amountVoltIn).toInt256(),
            amountOut.toInt256(),
            0
        );
        assertApproxEqPpq(
            psm.getRedeemAmountOut(amountVoltIn).toInt256(),
            amountOut.toInt256(),
            1_000_000_000
        );
    }

    /// @notice PSM is set up correctly and view functions are working
    function testGetMintAmountOut(uint128 amountDaiIn) public {
        uint256 currentPegPrice = oracle.getCurrentOraclePrice();
        uint256 amountOut = (uint256(amountDaiIn) * 1e18) / currentPegPrice;
        assertApproxEq(
            psm.getMintAmountOut(amountDaiIn).toInt256(),
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
            psm.getMintAmountOut(amountDaiIn).toInt256(),
            amountOut.toInt256(),
            0
        );
    }

    function testMintFuzz(uint32 amountStableIn) public {
        uint256 amountVoltOut = psm.getMintAmountOut(amountStableIn);
        uint256 startingVoltTotalSupply = volt.totalSupply();
        uint256 startingpsmBalance = psm.balance();
        uint256 startingUserVoltBalance = volt.balanceOf(address(this));
        uint256 startingBuffer = grlm.buffer();

        underlyingToken.approve(address(psm), amountStableIn);
        psm.mint(address(this), amountStableIn, amountVoltOut);

        uint256 endingVoltTotalSupply = volt.totalSupply();
        uint256 endingUserVoltBalance = volt.balanceOf(address(this));
        uint256 endingpsmBalance = psm.balance();
        uint256 endingBuffer = grlm.buffer();

        assertEq(startingBuffer - endingBuffer, amountVoltOut);

        assertEq(
            startingVoltTotalSupply + amountVoltOut,
            endingVoltTotalSupply
        );

        assertEq(
            endingUserVoltBalance - amountVoltOut,
            startingUserVoltBalance
        );

        /// assert psm receives amount stable in
        assertEq(endingpsmBalance - startingpsmBalance, amountStableIn);
    }

    function testMintFuzzNotEnoughIn(uint32 amountStableIn) public {
        uint256 amountVoltOut = psm.getMintAmountOut(amountStableIn);
        underlyingToken.approve(address(psm), amountStableIn);
        vm.expectRevert("PegStabilityModule: Mint not enough out");
        psm.mint(address(this), amountStableIn, amountVoltOut + 1);
    }

    function testRedeemFuzz(uint32 amountVoltIn) public {
        uint256 amountOut = psm.getRedeemAmountOut(amountVoltIn);

        uint256 currentPegPrice = oracle.getCurrentOraclePrice();
        uint256 underlyingOutOracleAmount = (amountVoltIn * currentPegPrice) /
            1e18;

        uint256 startingUserUnderlyingBalance = underlyingToken.balanceOf(
            address(this)
        );
        uint256 startingPsmUnderlyingBalance = psm.balance();
        uint256 startingUserVoltBalance = volt.balanceOf(address(this));

        volt.approve(address(psm), amountVoltIn);
        psm.redeem(address(this), amountVoltIn, amountOut);

        uint256 endingUserUnderlyingBalance1 = underlyingToken.balanceOf(
            address(this)
        );

        uint256 endingUserVoltBalance = volt.balanceOf(address(this));
        uint256 endingPsmUnderlyingBalance = psm.balance();
        assertEq(
            startingPsmUnderlyingBalance - endingPsmUnderlyingBalance,
            amountOut
        );
        assertEq(startingUserVoltBalance - endingUserVoltBalance, amountVoltIn);
        assertEq(
            endingUserUnderlyingBalance1,
            startingUserUnderlyingBalance + amountOut
        );
        assertApproxEq(
            underlyingOutOracleAmount.toInt256(),
            amountOut.toInt256(),
            0
        );
    }

    function testRedeemFuzzNotEnoughOut(uint32 amountVoltIn) public {
        uint256 amountOut = psm.getRedeemAmountOut(amountVoltIn);

        volt.approve(address(psm), amountVoltIn);
        vm.expectRevert("PegStabilityModule: Redeem not enough out");
        psm.redeem(address(this), amountVoltIn, amountOut + 1);
    }

    /// @notice pcv deposit receives underlying token on mint
    function testSwapUnderlyingForVolt() public {
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

    /// @notice redeem fails without approval
    function testSwapVoltForunderlyingTokenFailsWithoutApproval() public {
        vm.expectRevert("ERC20: insufficient allowance");
        psm.redeem(address(this), mintAmount, mintAmount);
    }

    function testMintFailsWhenMintExceedsBuffer() public {
        underlyingToken.approve(address(psm), type(uint256).max);
        uint256 currentPegPrice = oracle.getCurrentOraclePrice();
        uint256 psmVoltBalance = grlm.buffer() + 1; /// try to mint 1 wei over buffer which causes failure
        /// we get the amount we want to put in by getting the
        /// total PSM balance and dividing by the current peg price
        /// this lets us get the maximum amount we can deposit
        uint256 amountIn = (psmVoltBalance * currentPegPrice) / 1e6;
        // this will revert (correctly) as the math above is less precise than the PSMs, therefore our amountIn
        // will slightly exceed the balance the PSM can give to us.
        vm.expectRevert("RateLimited: rate limit hit");
        psm.mint(address(this), amountIn, psmVoltBalance);
    }

    /// @notice mint fails without approval
    function testSwapUnderlyingForVoltFailsWithoutApproval() public {
        vm.expectRevert("ERC20: insufficient allowance");
        psm.mint(address(this), mintAmount, 0);
    }

    /// @notice withdraw succeeds with correct permissions
    function testWithdrawSuccess() public {
        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(this));
        uint256 startingBalance = underlyingToken.balanceOf(address(this));
        psm.withdraw(address(this), mintAmount);
        uint256 endingBalance = underlyingToken.balanceOf(address(this));
        assertEq(endingBalance - startingBalance, mintAmount);
    }

    /// @notice withdraw fails without correct permissions
    function testWithdrawFailure() public {
        vm.expectRevert(bytes("CoreRef: Caller is not a PCV controller"));
        psm.withdraw(address(this), 100);
    }

    /// @notice withdraw erc20 fails without correct permissions
    function testERC20WithdrawFailure() public {
        vm.expectRevert(bytes("CoreRef: Caller is not a PCV controller"));
        psm.withdrawERC20(address(underlyingToken), address(this), 100);
    }

    /// @notice withdraw erc20 succeeds with correct permissions
    function testERC20WithdrawSuccess() public {
        vm.prank(addresses.governorAddress);
        core.grantPCVController(address(this));
        uint256 startingBalance = underlyingToken.balanceOf(address(this));
        psm.withdrawERC20(address(underlyingToken), address(this), mintAmount);
        uint256 endingBalance = underlyingToken.balanceOf(address(this));
        assertEq(endingBalance - startingBalance, mintAmount);
    }

    function testDepositNoOp() public {
        psm.deposit();
    }

    /// @notice deposit fails when paused
    function testDepositFailsWhenPaused() public {
        vm.prank(addresses.governorAddress);
        psm.pause();
        vm.expectRevert("Pausable: paused");
        psm.deposit();
    }
}
