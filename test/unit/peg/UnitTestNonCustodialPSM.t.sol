// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {Test, console} from "@forge-std/Test.sol";
import {CoreV2} from "@voltprotocol/core/CoreV2.sol";
import {Constants} from "@voltprotocol/Constants.sol";
import {Deviation} from "@test/unit/utils/Deviation.sol";
import {VoltRoles} from "@voltprotocol/core/VoltRoles.sol";
import {MockERC20} from "@test/mock/MockERC20.sol";
import {PCVDeposit} from "@voltprotocol/pcv/PCVDeposit.sol";
import {PCVGuardian} from "@voltprotocol/pcv/PCVGuardian.sol";
import {SystemEntry} from "@voltprotocol/entry/SystemEntry.sol";
import {IPCVDepositV2} from "@voltprotocol/pcv/IPCVDepositV2.sol";
import {NonCustodialPSM} from "@voltprotocol/peg/NonCustodialPSM.sol";
import {MockPCVDepositV3} from "@test/mock/MockPCVDepositV3.sol";
import {VoltSystemOracle} from "@voltprotocol/oracle/VoltSystemOracle.sol";
import {TestAddresses as addresses} from "@test/unit/utils/TestAddresses.sol";
import {getCoreV2, getVoltSystemOracle} from "@test/unit/utils/Fixtures.sol";
import {IGlobalReentrancyLock, GlobalReentrancyLock} from "@voltprotocol/core/GlobalReentrancyLock.sol";
import {IGlobalRateLimitedMinter, GlobalRateLimitedMinter} from "@voltprotocol/rate-limits/GlobalRateLimitedMinter.sol";

/// deployment steps
/// 1. core v2
/// 2. Volt system oracle
/// 3. oracle pass through
/// 4. custodial peg stability module
/// 5. non custodial peg stability module
/// 6. pcv deposit

/// setup steps
/// 1. grant pcv guardian pcv controller role
/// 2. grant erc20 allocator pcv controller role
/// 3. grant compound pcv router pcv controller role
/// 4. grant pcv guardian guardian role
/// 5. grant pcv guard role to EOA's
/// 6. configure timelock as owner of oracle pass through
/// 7. revoke timelock admin rights from deployer
/// 8. grant timelock governor
/// 9. connect pcv deposits to psm in allocator

/// PSM target balance is 10k cash for both deposits

/// test steps
/// 1. do swaps in psm
/// 2. do emergency action to pull funds
/// 3. do sweep to pull funds
/// 4. do pcv guardian withdraw as EOA

interface IERC20Mintable is IERC20 {
    function mint(address, uint256) external;
}

contract NonCustodialPSMUnitTest is Test {
    using SafeCast for *;

    event PCVDepositUpdate(address oldTarget, address newPCVDeposit);

    CoreV2 private core;
    SystemEntry private entry;
    IERC20Mintable private dai;
    IERC20Mintable private volt;
    NonCustodialPSM private psm;
    VoltSystemOracle private oracle;
    GlobalRateLimitedMinter private grlm;
    MockPCVDepositV3 private pcvDeposit;
    IGlobalReentrancyLock private lock;

    address private voltAddress;
    address private coreAddress;

    uint256 public constant timelockDelay = 600;
    uint248 public constant usdcTargetBalance = 100_000e6;
    uint248 public constant daiTargetBalance = 100_000e18;
    int8 public constant usdcDecimalsNormalizer = 12;
    int8 public constant daiDecimalsNormalizer = 0;

    /// ---------- GRLM PARAMS ----------

    /// maximum rate limit per second is 100 VOLT
    uint256 public constant maxRateLimitPerSecondMinting = 100e18;

    /// replenish 500k VOLT per day
    uint64 public constant rateLimitPerSecondMinting = 5.787e18;

    /// buffer cap of 1.5m VOLT
    uint96 public constant bufferCapMinting = 1_500_000e18;

    /// ---------- ALLOCATOR PARAMS ----------

    uint256 public constant maxRateLimitPerSecond = 1_000e18; /// 1k volt per second
    uint128 public constant rateLimitPerSecond = 10e18; /// 10 volt per second
    uint128 public constant bufferCap = type(uint128).max; /// buffer cap is 2^128-1

    /// ---------- PSM PARAMS ----------

    uint128 public constant voltFloorPrice = 1.05e18; /// 1 volt for 1.05 dai is the minimum price
    uint128 public constant voltCeilingPrice = 1.1e18; /// 1 volt for 1.1 dai is the max allowable price

    /// ---------- ORACLE PARAMS ----------

    uint112 public constant monthlyChangeRate = 0.01e18; /// 100 basis points
    uint112 public constant startPrice = 1.05e18;
    uint32 public constant startTime = 1_000;

    function setUp() public {
        vm.warp(startTime); /// warp past 0
        core = getCoreV2();
        volt = IERC20Mintable(address(core.volt()));
        voltAddress = address(volt);
        coreAddress = address(core);
        lock = IGlobalReentrancyLock(
            address(new GlobalReentrancyLock(address(core)))
        );
        entry = new SystemEntry(address(core));
        dai = IERC20Mintable(address(new MockERC20()));
        oracle = getVoltSystemOracle(
            coreAddress,
            monthlyChangeRate,
            startTime,
            startPrice
        );
        grlm = new GlobalRateLimitedMinter(
            coreAddress,
            maxRateLimitPerSecondMinting,
            rateLimitPerSecondMinting,
            bufferCapMinting
        );

        pcvDeposit = new MockPCVDepositV3(coreAddress, address(dai));

        psm = new NonCustodialPSM(
            coreAddress,
            address(oracle),
            address(0),
            0,
            false,
            dai,
            voltFloorPrice,
            voltCeilingPrice,
            IPCVDepositV2(address(pcvDeposit))
        );

        vm.startPrank(addresses.governorAddress);

        core.grantPCVController(address(psm));
        core.grantMinter(address(grlm));

        core.grantPsmMinter(address(psm));

        core.grantLocker(address(entry));
        core.grantLocker(address(psm));
        core.grantLocker(address(pcvDeposit));
        core.grantLocker(address(grlm));

        core.setGlobalRateLimitedMinter(
            IGlobalRateLimitedMinter(address(grlm))
        );
        core.setGlobalReentrancyLock(lock);

        vm.stopPrank();

        /// top up contracts with tokens for testing
        dai.mint(address(pcvDeposit), daiTargetBalance);
        entry.deposit(address(pcvDeposit));

        vm.label(address(psm), "psm");
        vm.label(address(pcvDeposit), "pcvDeposit");
        vm.label(address(this), "address this");
    }

    function testSetup() public {
        assertTrue(core.isLocker(address(psm)));

        assertTrue(core.isMinter(address(grlm)));
        assertTrue(core.isPsmMinter(address(psm)));
        assertTrue(core.isPCVController(address(psm)));

        assertEq(address(core.globalRateLimitedMinter()), address(grlm));
        assertEq(oracle.monthlyChangeRate(), monthlyChangeRate);

        assertEq(psm.floor(), voltFloorPrice);
        assertEq(psm.ceiling(), voltCeilingPrice);
        assertEq(address(psm.pcvDeposit()), address(pcvDeposit));
        assertEq(psm.decimalsNormalizer(), 0);
        assertEq(address(psm.underlyingToken()), address(dai));
    }

    function testGetMaxRedeemAmountIn() public {
        uint256 buffer = grlm.buffer();
        uint256 oraclePrice = psm.readOracle();

        uint256 pcvDepositBalance = pcvDeposit.balance();

        assertEq(
            psm.getMaxRedeemAmountIn(),
            (Math.min(buffer, pcvDepositBalance) * Constants.ETH_GRANULARITY) /
                oraclePrice
        );
    }

    function testExitValueInversionPositive(uint96 amount) public {
        psm = new NonCustodialPSM(
            coreAddress,
            address(oracle),
            address(0),
            12,
            false,
            dai,
            voltFloorPrice,
            voltCeilingPrice,
            IPCVDepositV2(address(pcvDeposit))
        );

        assertEq(psm.getExitValue(amount), amount / (1e12));
    }

    function testExitValueInversionNegative(uint96 amount) public {
        psm = new NonCustodialPSM(
            coreAddress,
            address(oracle),
            address(0),
            -12,
            false,
            dai,
            voltFloorPrice,
            voltCeilingPrice,
            IPCVDepositV2(address(pcvDeposit))
        );

        assertEq(psm.getExitValue(amount), uint256(amount) * (1e12));
    }

    function testExitValueNormalizerZero(uint256 amount) public {
        assertEq(psm.getExitValue(amount), amount);
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

    /// @notice PSM is set up correctly and redeem view function is working
    function testGetRedeemAmountOutDifferential(uint128 amountVoltIn) public {
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

    function testRedeemFuzz(uint128 redeemAmount) public {
        vm.assume(redeemAmount != 0);
        uint256 amountOut;

        uint256 voltBalance = volt.balanceOf(address(this));
        uint256 underlyingAmountOut = psm.getRedeemAmountOut(voltBalance);
        uint256 userStartingUnderlyingBalance = dai.balanceOf(address(this));
        uint256 depositStartingUnderlyingBalance = pcvDeposit.balance();
        amountOut = underlyingAmountOut;

        volt.approve(address(psm), voltBalance);
        assertEq(
            underlyingAmountOut,
            psm.redeem(address(this), voltBalance, underlyingAmountOut)
        );
        console.log("successfully redeemed");
        console.log("bufferCap: ", bufferCap);
        console.log("underlyingAmountOut: ", underlyingAmountOut);
        console.log(
            "bufferCap - underlyingAmountOut: ",
            bufferCap - underlyingAmountOut
        );

        assertEq(bufferCap - underlyingAmountOut, grlm.midPoint());

        uint256 depositEndingUnderlyingBalance = pcvDeposit.balance();
        uint256 userEndingUnderlyingBalance = dai.balanceOf(address(this));
        uint256 bufferAfterRedeem = grlm.buffer();

        uint256 endingBalance = dai.balanceOf(address(this));

        console.log("asserted midpoint");
        assertEq(endingBalance, underlyingAmountOut);
        console.log("asserted amounts out");

        assertEq(
            depositStartingUnderlyingBalance - depositEndingUnderlyingBalance,
            underlyingAmountOut
        );
        console.log("asserted deposit amounts out");

        assertEq(bufferAfterRedeem, amountOut);
        // assertEq(bufferAfterRedeem, grlm.buffer());
        assertEq(
            userEndingUnderlyingBalance - underlyingAmountOut,
            userStartingUnderlyingBalance
        );
        assertEq(volt.balanceOf(address(psm)), 0);
    }

    function testRedeemDifferentialSucceeds(uint128 redeemAmount) public {
        vm.assume(redeemAmount != 0);

        uint256 voltBalance = volt.balanceOf(address(this));
        uint256 underlyingAmountOut = psm.getRedeemAmountOut(voltBalance);
        uint256 userStartingUnderlyingBalance = dai.balanceOf(address(this));
        uint256 depositStartingUnderlyingBalance = pcvDeposit.balance();

        volt.approve(address(psm), voltBalance);
        assertEq(
            underlyingAmountOut,
            psm.redeem(address(this), voltBalance, underlyingAmountOut)
        );

        uint256 depositEndingUnderlyingBalance = pcvDeposit.balance();
        uint256 userEndingUnderlyingBalance = dai.balanceOf(address(this));
        uint256 bufferAfterRedeem = grlm.buffer();

        uint256 endingBalance = dai.balanceOf(address(this));

        assertEq(endingBalance, underlyingAmountOut);

        assertEq(
            depositStartingUnderlyingBalance - depositEndingUnderlyingBalance,
            underlyingAmountOut
        );

        assertEq(bufferCap - underlyingAmountOut, grlm.buffer());

        assertEq(bufferAfterRedeem, grlm.bufferCap());
        assertEq(bufferAfterRedeem, grlm.buffer());
        assertEq(
            userEndingUnderlyingBalance - underlyingAmountOut,
            userStartingUnderlyingBalance
        );
        assertEq(volt.balanceOf(address(psm)), 0);
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
            testRedeemFuzz(100_000);
        } else if (newFloorPrice >= currentCeiling) {
            vm.expectRevert(
                "PegStabilityModule: floor must be less than ceiling"
            );
            vm.prank(addresses.governorAddress);
            psm.setOracleFloorPrice(newFloorPrice);
            assertTrue(psm.isPriceValid());
            testRedeemFuzz(100_000);
        } else if (newFloorPrice > currentPrice) {
            vm.prank(addresses.governorAddress);
            psm.setOracleFloorPrice(newFloorPrice);
            assertTrue(!psm.isPriceValid());

            vm.expectRevert("PegStabilityModule: price out of bounds");
            psm.redeem(address(this), 1, 0);
        }
    }

    function testSetPCVDepositGovernorSucceeds() public {
        IPCVDepositV2 newDeposit = IPCVDepositV2(
            address(new MockPCVDepositV3(coreAddress, address(dai)))
        );
        vm.expectEmit(true, true, false, true, address(psm));
        emit PCVDepositUpdate(address(pcvDeposit), address(newDeposit));
        vm.prank(addresses.governorAddress);
        psm.setPCVDeposit(newDeposit);

        assertEq(address(psm.pcvDeposit()), address(newDeposit));
    }

    function testSetPCVDepositGovernorFailsMismatchUnderlyingToken() public {
        IPCVDepositV2 newDeposit = IPCVDepositV2(
            address(new MockPCVDepositV3(coreAddress, address(12345)))
        );
        vm.prank(addresses.governorAddress);
        vm.expectRevert("PegStabilityModule: Underlying token mismatch");
        psm.setPCVDeposit(newDeposit);
    }

    /// ----------- ACL TESTS -----------

    function testSetOracleFloorPriceNonGovernorFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        psm.setOracleFloorPrice(100);
    }

    function testSetPCVDepositNonGovernorFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        psm.setPCVDeposit(IPCVDepositV2(address(0)));
    }

    function testSetOracleCeilingPriceNonGovernorFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        psm.setOracleCeilingPrice(100);
    }
}
