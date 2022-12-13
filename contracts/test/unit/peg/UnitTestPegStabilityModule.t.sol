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
import {SystemEntry} from "../../../entry/SystemEntry.sol";
import {Test, console2} from "../../../../forge-std/src/Test.sol";
import {NonCustodialPSM} from "../../../peg/NonCustodialPSM.sol";
import {VoltSystemOracle} from "../../../oracle/VoltSystemOracle.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";
import {TestAddresses as addresses} from "../utils/TestAddresses.sol";
import {getCoreV2, getLocalOracleSystem} from "./../../unit/utils/Fixtures.sol";
import {IGlobalReentrancyLock, GlobalReentrancyLock} from "../../../core/GlobalReentrancyLock.sol";
import {IGlobalRateLimitedMinter, GlobalRateLimitedMinter} from "../../../limiter/GlobalRateLimitedMinter.sol";

/// PSM Unit Test that tests new PSM to ensure proper behavior
contract UnitTestPegStabilityModule is Test {
    using SafeCast for *;

    /// @notice PSM to test against
    PegStabilityModule private psm;

    IVolt private volt;
    ICoreV2 private core;
    SystemEntry private entry;
    IERC20 private underlyingToken;
    PCVGuardian private pcvGuardian;
    VoltSystemOracle private oracle;
    IGlobalReentrancyLock private lock;
    GlobalRateLimitedMinter private grlm;

    uint256 public constant mintAmount = 10_000_000e18;
    uint256 public constant voltMintAmount = 10_000_000e18;

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
        (oracle, ) = getLocalOracleSystem(address(core), voltFloorPrice);
        lock = IGlobalReentrancyLock(
            address(new GlobalReentrancyLock(address(core)))
        );

        /// create PSM
        psm = new PegStabilityModule(
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
        grlm = new GlobalRateLimitedMinter(
            address(core),
            maxRateLimitPerSecondMinting,
            rateLimitPerSecondMinting,
            bufferCapMinting
        );
        entry = new SystemEntry(address(core));

        address[] memory toWhitelist = new address[](1);
        toWhitelist[0] = address(psm);

        pcvGuardian = new PCVGuardian(
            address(core),
            address(this),
            toWhitelist
        );

        vm.startPrank(addresses.governorAddress);

        core.setGlobalRateLimitedMinter(
            IGlobalRateLimitedMinter(address(grlm))
        );
        core.setGlobalReentrancyLock(lock);

        core.grantPCVController(address(pcvGuardian));

        core.grantMinter(address(grlm));

        core.grantRateLimitedRedeemer(address(psm));
        core.grantRateLimitedMinter(address(psm));

        core.grantGuardian(address(pcvGuardian));

        core.grantPCVGuard(address(this));

        core.grantLocker(address(psm));
        core.grantLocker(address(grlm));
        core.grantLocker(address(entry));
        core.grantLocker(address(pcvGuardian));

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
        assertEq(address(psm.oracle()), address(oracle));
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

    function testMintFuzz(uint72 amountStableIn) public {
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

    function testRedeemFuzz(uint72 amountVoltIn) public {
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

    function testRedeemFuzzNotEnoughOut(uint96 amountVoltIn) public {
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
        uint256 startingBalance = underlyingToken.balanceOf(address(this));
        pcvGuardian.withdrawToSafeAddress(address(psm), mintAmount);
        uint256 endingBalance = underlyingToken.balanceOf(address(this));
        assertEq(endingBalance - startingBalance, mintAmount);
    }

    function testSetOracleFloorPriceGovernorSucceeds() public {
        uint128 currentPrice = uint128(oracle.getCurrentOraclePrice());
        vm.prank(addresses.governorAddress);
        psm.setOracleFloorPrice(currentPrice);
        assertTrue(psm.isPriceValid());
    }

    function testSetOracleCeilingPriceGovernorSucceeds() public {
        uint128 currentPrice = uint128(oracle.getCurrentOraclePrice());
        vm.prank(addresses.governorAddress);
        psm.setOracleCeilingPrice(currentPrice + 1);
        assertTrue(psm.isPriceValid());
    }

    function testSetOracleCeilingPriceGovernorLteFloorFails() public {
        uint128 currentFloor = psm.floor();

        vm.startPrank(addresses.governorAddress);

        vm.expectRevert(
            "PegStabilityModule: ceiling must be greater than floor"
        );
        psm.setOracleCeilingPrice(currentFloor);

        vm.expectRevert(
            "PegStabilityModule: ceiling must be greater than floor"
        );
        psm.setOracleCeilingPrice(currentFloor - 1);

        vm.stopPrank();
    }

    function testSetOracleFloorPrice0GovernorFails() public {
        vm.expectRevert("PegStabilityModule: invalid floor");
        vm.prank(addresses.governorAddress);
        psm.setOracleFloorPrice(0);
    }

    function testSetOracleFloorPriceGovernorSucceedsFuzz(
        uint128 newFloorPrice
    ) public {
        vm.assume(newFloorPrice != 0);

        uint128 currentPrice = uint128(oracle.getCurrentOraclePrice());
        uint128 currentFloor = psm.floor();
        uint128 currentCeiling = psm.ceiling();

        if (newFloorPrice < currentFloor) {
            vm.prank(addresses.governorAddress);
            psm.setOracleFloorPrice(newFloorPrice);
            assertTrue(psm.isPriceValid());
            testMintFuzz(100_000);
            testRedeemFuzz(100_000);
        } else if (newFloorPrice >= currentCeiling) {
            vm.expectRevert(
                "PegStabilityModule: floor must be less than ceiling"
            );
            vm.prank(addresses.governorAddress);
            psm.setOracleFloorPrice(newFloorPrice);
            assertTrue(psm.isPriceValid());
            testMintFuzz(100_000);
            testRedeemFuzz(100_000);
        } else if (newFloorPrice > currentPrice) {
            vm.prank(addresses.governorAddress);
            psm.setOracleFloorPrice(newFloorPrice);
            assertTrue(!psm.isPriceValid());

            vm.expectRevert("PegStabilityModule: price out of bounds");
            psm.mint(address(this), 1, 0);
            vm.expectRevert("PegStabilityModule: price out of bounds");
            psm.redeem(address(this), 1, 0);
        }
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
        entry.deposit(address(psm));
    }

    /// @notice deposit fails when paused
    function testDepositFailsWhenPaused() public {
        vm.prank(addresses.governorAddress);
        psm.pause();
        vm.expectRevert("Pausable: paused");
        entry.deposit(address(psm));
    }

    /// ----------- ACL TESTS -----------

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

    function testSetOracleFloorPriceNonGovernorFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        psm.setOracleFloorPrice(100);
    }

    function testSetOracleCeilingPriceNonGovernorFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        psm.setOracleCeilingPrice(100);
    }
}
