// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {Vm} from "./../unit/utils/Vm.sol";
import {Core} from "../../core/Core.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {ICoreV2} from "../../core/ICoreV2.sol";
import {Constants} from "../../Constants.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {getCoreV2} from "./../unit/utils/Fixtures.sol";
import {IVolt, Volt} from "../../volt/Volt.sol";
import {IPCVDeposit} from "../../pcv/IPCVDeposit.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {MockPCVDepositV2} from "../../mock/MockPCVDepositV2.sol";
import {IOraclePassThrough} from "../../oracle/IOraclePassThrough.sol";
import {PegStabilityModule} from "../../peg/PegStabilityModule.sol";
import {ERC20CompoundPCVDeposit} from "../../pcv/compound/ERC20CompoundPCVDeposit.sol";
import {IGlobalRateLimitedMinter, GlobalRateLimitedMinter} from "../../limiter/GlobalRateLimitedMinter.sol";
import {TestAddresses as addresses} from "../unit/utils/TestAddresses.sol";
import {IGlobalReentrancyLock, GlobalReentrancyLock} from "../../core/GlobalReentrancyLock.sol";

contract IntegrationTestPriceBoundPSMUSDCTest is DSTest {
    using SafeCast for *;

    IVolt private volt;
    ICoreV2 private core;
    PegStabilityModule private psm;
    IGlobalReentrancyLock public lock;
    GlobalRateLimitedMinter public grlm;
    IERC20 private usdc = IERC20(MainnetAddresses.USDC);
    IERC20 private underlyingToken = usdc;

    address public makerUSDCPSM = MainnetAddresses.KRAKEN_USDC_WHALE;

    /// ------------ Minting and RateLimited System Params ------------

    uint256 public constant mintAmount = 10_000_000e6;
    uint256 public constant voltMintAmount = 10_000_000e18;

    /// @notice Oracle Pass Through contract
    IOraclePassThrough public oracle =
        IOraclePassThrough(MainnetAddresses.ORACLE_PASS_THROUGH);

    Vm public constant vm = Vm(HEVM_ADDRESS);

    uint128 voltFloorPrice = 1.05e6; /// 1 volt for 1.05 usdc is the min pirce
    uint128 voltCeilingPrice = 1.1e6; /// 1 volt for 1.1 usdc is the max price

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
        lock = IGlobalReentrancyLock(
            address(new GlobalReentrancyLock(address(core)))
        );

        /// create PSM
        psm = new PegStabilityModule(
            address(core),
            address(oracle),
            address(0),
            -12,
            false,
            IERC20(address(usdc)),
            voltFloorPrice,
            voltCeilingPrice
        );
        grlm = new GlobalRateLimitedMinter(
            address(core),
            maxRateLimitPerSecondMinting,
            rateLimitPerSecondMinting,
            bufferCapMinting
        );

        vm.startPrank(addresses.governorAddress);

        core.setGlobalRateLimitedMinter(
            IGlobalRateLimitedMinter(address(grlm))
        );
        core.setGlobalReentrancyLock(lock);

        core.grantLocker(address(grlm)); /// allow setting of reentrancy lock
        core.grantMinter(address(grlm));

        core.grantRateLimitedRedeemer(address(psm));
        core.grantRateLimitedMinter(address(psm));
        core.grantLocker(address(psm));

        vm.stopPrank();

        vm.label(address(psm), "PSM");
        vm.label(address(core), "core");
        vm.label(address(grlm), "global rate limited minter");
        vm.label(address(volt), "volt");
        vm.label(address(usdc), "usdc");
        vm.label(address(oracle), "oracle");

        uint256 balance = usdc.balanceOf(makerUSDCPSM);
        vm.prank(makerUSDCPSM);
        usdc.transfer(address(this), balance);

        /// grant the PSM the PCV Controller role
        /// mint VOLT to the user
        volt.mint(address(psm), voltMintAmount);
        volt.mint(address(this), voltMintAmount);

        usdc.transfer(address(psm), balance / 2);
    }

    /// @notice PSM is set up correctly
    function testSetUpCorrectly() public {
        assertTrue(!psm.doInvert());
        assertTrue(psm.isPriceValid());
        assertEq(psm.floor(), voltFloorPrice);
        assertEq(psm.ceiling(), voltCeilingPrice);
        assertEq(address(psm.oracle()), address(oracle));
        assertEq(address(psm.backupOracle()), address(0));
        assertEq(psm.decimalsNormalizer(), -12);
        assertEq(address(psm.underlyingToken()), address(usdc));
        assertEq(address(core.globalRateLimitedMinter()), address(grlm));
    }

    /// @notice PSM is set up correctly and redeem view function is working
    function testGetRedeemAmountOut() public {
        uint256 amountVoltIn = 100e18;
        uint256 currentPegPrice = oracle.getCurrentOraclePrice() / 1e12;

        uint256 amountOut = ((amountVoltIn * currentPegPrice) / 1e18);

        assertApproxEq(
            psm.getRedeemAmountOut(amountVoltIn).toInt256(),
            amountOut.toInt256(),
            1
        );
    }

    /// @notice PSM is set up correctly and view functions are working
    function testGetMaxMintAmountOut() public {
        assertEq(psm.getMaxMintAmountOut(), grlm.buffer());
    }

    /// @notice PSM is set up correctly and view functions are working
    function testGetMintAmountOut() public {
        uint256 amountUSDCIn = 100e18;
        uint256 currentPegPrice = oracle.getCurrentOraclePrice();

        // The USDC PSM returns a result scaled up 1e12, so we scale the amountOut and fee
        // by this same amount to maintain precision

        uint256 amountOut = (((amountUSDCIn * 1e18) / currentPegPrice)) * 1e12;

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
        vm.expectRevert("ERC20: insufficient allowance");

        psm.redeem(address(this), mintAmount, mintAmount / 1e12);
    }

    /// @notice mint fails without approval
    function testSwapUnderlyingForVoltFailsWithoutApproval() public {
        vm.expectRevert("ERC20: transfer amount exceeds allowance");

        psm.mint(address(this), mintAmount, 0);
    }

    /// @notice withdraw erc20 fails without correct permissions
    function testERC20WithdrawFailure() public {
        vm.expectRevert("CoreRef: Caller is not a PCV controller");

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
}
