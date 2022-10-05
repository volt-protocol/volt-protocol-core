// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
// import {Vm} from "./../unit/utils/Vm.sol";
import {Core} from "../../core/Core.sol";
import {ICore} from "../../core/ICore.sol";
import {CoreV2} from "../../core/CoreV2.sol";
// import {DSTest} from "./../unit/utils/DSTest.sol";
import {VoltRoles} from "../../core/VoltRoles.sol";
import {Constants} from "../../Constants.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {IVolt, Volt} from "../../volt/Volt.sol";
import {IPCVDeposit} from "../../pcv/IPCVDeposit.sol";
import {PriceBoundPSMV2} from "../../peg/PriceBoundPSMV2.sol";
import {MockPCVDepositV2} from "../../mock/MockPCVDepositV2.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {OraclePassThrough} from "../../oracle/OraclePassThrough.sol";
import {ERC20HoldingPCVDeposit} from "../../pcv/ERC20HoldingPCVDeposit.sol";
import {GlobalRateLimitedMinter} from "../../minter/GlobalRateLimitedMinter.sol";
import {getCore, getMainnetAddresses, VoltTestAddresses} from "../unit/utils/Fixtures.sol";

import "forge-std/Test.sol";

contract IntegrationTestPriceBoundPSMV2 is Test {
    using SafeCast for *;

    PriceBoundPSMV2 private priceBoundPsm;
    ERC20HoldingPCVDeposit private pcvDeposit;
    GlobalRateLimitedMinter private grlm;

    CoreV2 private core;
    IVolt private volt;
    IERC20 private usdc = IERC20(MainnetAddresses.USDC);
    IERC20 private underlyingToken = usdc;

    uint256 public constant mintAmount = 10_000_000e6;
    uint256 public constant voltMintAmount = 10_000_000e18;

    /// maximum rate limit per second is 100 VOLT
    uint256 public constant maxRateLimitPerSecond = 100e18;

    /// replenish 500k VOLT per day
    uint128 public constant rateLimitPerSecond = 5.787e18;

    /// buffer cap of 1.5m VOLT
    uint128 public constant bufferCap = 1_500_000e18;

    /// @notice Oracle Pass Through contract
    OraclePassThrough public oracle =
        OraclePassThrough(MainnetAddresses.ORACLE_PASS_THROUGH);

    uint128 voltFloorPrice = 1_000_000;
    uint128 voltCeilingPrice = 1_100_000;

    function setUp() public {
        volt = Volt(address(new MockERC20()));
        core = new CoreV2(address(volt), address(0));
        pcvDeposit = new ERC20HoldingPCVDeposit(
            address(core),
            usdc,
            address(Constants.WETH)
        );

        grlm = new GlobalRateLimitedMinter(
            address(core),
            maxRateLimitPerSecond,
            rateLimitPerSecond,
            bufferCap
        );

        /// create PSM
        priceBoundPsm = new PriceBoundPSMV2(
            address(core),
            address(pcvDeposit),
            address(usdc),
            address(grlm),
            voltFloorPrice,
            voltCeilingPrice,
            address(oracle),
            address(0),
            -12
        );

        uint256 balance = 100_000_000e6;
        deal(address(usdc), address(this), balance);
        deal(address(usdc), address(pcvDeposit), balance);

        /// grant the PSM the PCV Controller role
        core.grantMinter(MainnetAddresses.GOVERNOR);
        core.grantMinter(address(grlm));
        core.grantMinter(address(this));
        core.grantPCVController(address(priceBoundPsm));
        core.createRole(VoltRoles.VOLT_MINTER_ROLE, VoltRoles.GOVERNOR);
        core.grantRole(VoltRoles.VOLT_MINTER_ROLE, address(priceBoundPsm));

        /// mint VOLT to the user
        volt.mint(address(priceBoundPsm), voltMintAmount);
        volt.mint(address(this), voltMintAmount);

        // usdc.transfer(address(priceBoundPsm), balance / 3);
    }

    /// @notice PSM is set up correctly
    function testSetUpCorrectly() public {
        assertTrue(!priceBoundPsm.doInvert());
        assertTrue(priceBoundPsm.isPriceValid());
        assertEq(priceBoundPsm.floorPrice(), voltFloorPrice);
        assertEq(priceBoundPsm.ceilingPrice(), voltCeilingPrice);
        assertEq(priceBoundPsm.decimalsNormalizer(), -12);
        assertEq(address(priceBoundPsm.oracle()), address(oracle));
        assertEq(address(priceBoundPsm.backupOracle()), address(0));
        assertEq(address(priceBoundPsm.grlm()), address(grlm));
        assertEq(address(priceBoundPsm.underlyingToken()), address(usdc));
    }

    // /// @notice PSM is set up correctly and redeem view function is working
    // function testGetRedeemAmountOut(uint128 amountVoltIn) public {
    //     uint256 currentPegPrice = oracle.getCurrentOraclePrice() / 1e12;

    //     uint256 amountOut = (amountVoltIn * currentPegPrice) / 1e18;

    //     assertApproxEq(
    //         priceBoundPsm.getRedeemAmountOut(amountVoltIn).toInt256(),
    //         amountOut.toInt256(),
    //         0
    //     );
    // }

    // /// @notice PSM is set up correctly and view functions are working
    // function testGetMintAmountOut(uint256 amountUSDCIn) public {

    //     vm.assume(usdc.balanceOf(address(this)) > amountUSDCIn);

    //     uint256 currentPegPrice = oracle.getCurrentOraclePrice() / 1e12;

    //     uint256 amountOut = (((amountUSDCIn * 1e18) / currentPegPrice));

    //     assertApproxEq(
    //         priceBoundPsm.getMintAmountOut(amountUSDCIn).toInt256(),
    //         priceBoundPsm.getMintAmountOut(amountUSDCIn).toInt256(),
    //         0
    //     );
    // }

    function testMintFuzz(uint32 amountStableIn) public {
        uint256 startingTotalSupply = volt.totalSupply();

        uint256 amountVoltOut = priceBoundPsm.getMintAmountOut(amountStableIn);

        uint256 amountVoltOutPriceBound = priceBoundPsm.getMintAmountOut(
            amountStableIn
        );

        uint256 startingUserVoltBalance = volt.balanceOf(address(this));
        uint256 startingPSMUnderlyingBalance = underlyingToken.balanceOf(
            address(pcvDeposit)
        );

        underlyingToken.approve(address(priceBoundPsm), amountStableIn);
        priceBoundPsm.mint(address(this), amountStableIn, amountVoltOut);

        uint256 endingUserVoltBalance1 = volt.balanceOf(address(this));
        uint256 endingPSMUnderlyingBalance = underlyingToken.balanceOf(
            address(pcvDeposit)
        );

        uint256 endingTotalSupply = volt.totalSupply();

        /// invariant on minting
        assertEq(startingTotalSupply + amountVoltOut, endingTotalSupply);

        assertEq(
            endingUserVoltBalance1,
            startingUserVoltBalance + amountVoltOut
        );

        assertEq(
            endingPSMUnderlyingBalance,
            startingPSMUnderlyingBalance + amountStableIn
        );
    }

    function testRedeemFuzz(uint32 amountVoltIn) public {
        uint256 startingTotalSupply = volt.totalSupply();
        uint256 amountOut = priceBoundPsm.getRedeemAmountOut(amountVoltIn);

        uint256 underlyingOutPriceBound = priceBoundPsm.getRedeemAmountOut(
            amountVoltIn
        );

        uint256 startingUserUnderlyingBalance = underlyingToken.balanceOf(
            address(this)
        );

        volt.approve(address(priceBoundPsm), amountVoltIn);
        priceBoundPsm.redeem(address(this), amountVoltIn, amountOut);

        uint256 endingUserUnderlyingBalance1 = underlyingToken.balanceOf(
            address(this)
        );
        uint256 endingPSMVoltBalance = volt.balanceOf(address(priceBoundPsm));

        uint256 endingUserUnderlyingBalance2 = underlyingToken.balanceOf(
            address(this)
        );

        uint256 endingTotalSupply = volt.totalSupply();

        /// invariant on burning
        assertEq(startingTotalSupply - amountVoltIn, endingTotalSupply);

        assertEq(
            endingUserUnderlyingBalance1,
            startingUserUnderlyingBalance + amountOut
        );

        assertEq(
            endingUserUnderlyingBalance2 - endingUserUnderlyingBalance1,
            underlyingOutPriceBound
        );
    }

    /// @notice pcv deposit receives underlying token on mint
    function testSwapUnderlyingForVolt() public {
        uint256 amountStableIn = 101_000;
        uint256 amountVoltOut = priceBoundPsm.getMintAmountOut(amountStableIn);
        uint256 startingUserVoltBalance = volt.balanceOf(address(this));
        uint256 startingPcvDepositUnderlyingBalance = underlyingToken.balanceOf(
            address(pcvDeposit)
        );

        underlyingToken.approve(address(priceBoundPsm), amountStableIn);
        priceBoundPsm.mint(address(this), amountStableIn, amountVoltOut);

        uint256 endingUserVoltBalance = volt.balanceOf(address(this));
        uint256 endingPcvDepositUnderlyingBalance = underlyingToken.balanceOf(
            address(pcvDeposit)
        );

        assertEq(
            endingUserVoltBalance,
            startingUserVoltBalance + amountVoltOut
        );
        assertEq(
            startingPcvDepositUnderlyingBalance + amountStableIn,
            endingPcvDepositUnderlyingBalance
        );
    }

    /// @notice redeem fails without approval
    function testSwapVoltForUSDCFailsWithoutApproval() public {
        vm.expectRevert("ERC20: insufficient allowance");

        priceBoundPsm.redeem(address(this), mintAmount, mintAmount / 1e12);
    }

    // /// @notice redeem fails without approval
    // function testMintFailsWhenMintExceedsPSMBalance() public {
    //     underlyingToken.approve(address(priceBoundPsm), type(uint256).max);

    //     uint256 currentPegPrice = oracle.getCurrentOraclePrice();
    //     uint256 psmVoltBalance = volt.balanceOf(address(priceBoundPsm));

    //     // we get the amount we want to put in by getting the total PSM balance and dividing by the current peg price
    //     // this lets us get the maximum amount we can deposit
    //     uint256 amountIn = (psmVoltBalance * currentPegPrice) / 1e6;

    //     // this will revert (correctly) as the math above is less precise than the PSMs, therefore our amountIn
    //     // will slightly exceed the balance the PSM can give to us.
    //     vm.expectRevert(bytes("ERC20: transfer amount exceeds balance"));

    //     priceBoundPsm.mint(address(this), amountIn, psmVoltBalance);
    // }

    /// @notice mint fails without approval
    function testSwapUnderlyingForVoltFailsWithoutApproval() public {
        vm.expectRevert(bytes("ERC20: transfer amount exceeds allowance"));

        priceBoundPsm.mint(address(this), mintAmount, 0);
    }

    /// @notice withdraw fails without correct permissions
    function testSweepFailure() public {
        core.revokePCVController(address(this));
        vm.expectRevert(bytes("CoreRef: Caller is not a PCV controller"));

        priceBoundPsm.sweep(address(usdc), address(this), 100);
    }

    /// @notice sweep usdc succeeds with correct permissions
    function testSweepSuccess() public {
        core.grantPCVController(address(this));

        deal(address(usdc), address(priceBoundPsm), mintAmount);

        uint256 startingBalance = underlyingToken.balanceOf(address(this));
        uint256 startingPsmBalance = underlyingToken.balanceOf(
            address(priceBoundPsm)
        );

        priceBoundPsm.sweep(address(usdc), address(this), startingPsmBalance);

        uint256 endingBalance = underlyingToken.balanceOf(address(this));
        uint256 endingPsmBalance = underlyingToken.balanceOf(
            address(priceBoundPsm)
        );

        assertEq(endingBalance - startingBalance, startingPsmBalance);
        assertEq(endingPsmBalance, 0);
    }
}
