// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Test} from "../../../../forge-std/src/Test.sol";
import {ICoreV2} from "../../../core/ICoreV2.sol";
import {Deviation} from "../../../utils/Deviation.sol";
import {VoltRoles} from "../../../core/VoltRoles.sol";
import {MockERC20} from "../../../mock/MockERC20.sol";
import {PCVDeposit} from "../../../pcv/PCVDeposit.sol";
import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";
import {IPCVDeposit} from "../../../pcv/IPCVDeposit.sol";
import {NonCustodialPSM} from "../../../peg/NonCustodialPSM.sol";
import {MockPCVDepositV3} from "../../../mock/MockPCVDepositV3.sol";
import {VoltSystemOracle} from "../../../oracle/VoltSystemOracle.sol";
import {OraclePassThrough} from "../../../oracle/OraclePassThrough.sol";
import {CompoundPCVRouter} from "../../../pcv/compound/CompoundPCVRouter.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";
import {IScalingPriceOracle} from "../../../oracle/IScalingPriceOracle.sol";
import {IGRLM, GlobalRateLimitedMinter} from "../../../minter/GlobalRateLimitedMinter.sol";
import {getCoreV2, getAddresses, getVoltAddresses, VoltAddresses, VoltTestAddresses} from "./../utils/Fixtures.sol";

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

    event PCVDepositUpdate(IPCVDeposit oldTarget, IPCVDeposit newPCVDeposit);

    VoltTestAddresses public addresses = getAddresses();
    VoltAddresses public guardianAddresses = getVoltAddresses();

    ICoreV2 private core;
    NonCustodialPSM private psm;
    PegStabilityModule private custodialPsm;
    MockPCVDepositV3 private pcvDeposit;
    VoltSystemOracle private vso;
    OraclePassThrough private opt;
    GlobalRateLimitedMinter public grlm;
    address private voltAddress;
    address private coreAddress;
    IERC20Mintable private dai;
    IERC20Mintable private volt;

    uint256 public constant timelockDelay = 600;
    uint248 public constant usdcTargetBalance = 100_000e6;
    uint248 public constant daiTargetBalance = 100_000e18;
    int8 public constant usdcDecimalsNormalizer = 12;
    int8 public constant daiDecimalsNormalizer = 0;

    /// ---------- GRLM PARAMS ----------

    /// maximum rate limit per second is 100 VOLT
    uint256 public constant maxRateLimitPerSecondMinting = 100e18;

    /// replenish 500k VOLT per day
    uint128 public constant rateLimitPerSecondMinting = 5.787e18;

    /// buffer cap of 1.5m VOLT
    uint128 public constant bufferCapMinting = 1_500_000e18;

    /// ---------- ALLOCATOR PARAMS ----------

    uint256 public constant maxRateLimitPerSecond = 1_000e18; /// 1k volt per second
    uint128 public constant rateLimitPerSecond = 10e18; /// 10 volt per second
    uint128 public constant bufferCap = 1_000_000e18; /// buffer cap is 1m volt

    /// ---------- PSM PARAMS ----------

    uint128 public constant voltFloorPrice = 1.05e18; /// 1 volt for 1.05 dai is the minimum price
    uint128 public constant voltCeilingPrice = 1.1e18; /// 1 volt for 1.1 dai is the max allowable price

    /// ---------- ORACLE PARAMS ----------

    uint256 public constant startPrice = 1.05e18;
    uint256 public constant startTime = 1_000;
    uint256 public constant monthlyChangeRateBasisPoints = 100;

    function setUp() public {
        vm.warp(startTime); /// warp past 0
        core = getCoreV2();
        volt = IERC20Mintable(address(core.volt()));
        voltAddress = address(volt);
        coreAddress = address(core);
        dai = IERC20Mintable(address(new MockERC20()));
        vso = new VoltSystemOracle(
            monthlyChangeRateBasisPoints,
            startTime,
            startPrice
        );
        opt = new OraclePassThrough(IScalingPriceOracle(address(vso)));
        grlm = new GlobalRateLimitedMinter(
            coreAddress,
            maxRateLimitPerSecondMinting,
            rateLimitPerSecondMinting,
            bufferCapMinting
        );

        pcvDeposit = new MockPCVDepositV3(coreAddress, address(dai));

        psm = new NonCustodialPSM(
            coreAddress,
            address(opt),
            address(0),
            0,
            false,
            dai,
            voltFloorPrice,
            voltCeilingPrice,
            IPCVDeposit(address(pcvDeposit))
        );

        custodialPsm = new PegStabilityModule(
            coreAddress,
            address(opt),
            address(0),
            0,
            false,
            dai,
            voltFloorPrice,
            voltCeilingPrice
        );

        vm.startPrank(addresses.governorAddress);

        core.grantPCVController(address(psm));
        core.grantMinter(address(grlm));

        core.grantRateLimitedRedeemer(address(psm));
        core.grantRateLimitedRedeemer(address(custodialPsm));

        core.grantLocker(address(psm));
        core.grantLocker(address(custodialPsm));
        core.grantLocker(address(pcvDeposit));
        core.grantLocker(address(grlm));

        core.setGlobalRateLimitedMinter(IGRLM(address(grlm)));

        vm.stopPrank();

        /// top up contracts with tokens for testing
        dai.mint(address(pcvDeposit), daiTargetBalance);
        dai.mint(address(custodialPsm), daiTargetBalance);
        pcvDeposit.deposit();

        vm.label(address(psm), "psm");
        vm.label(address(pcvDeposit), "pcvDeposit");
        vm.label(address(this), "address this");
    }

    function testSetup() public {
        assertTrue(core.isLocker(address(psm)));

        assertTrue(core.isMinter(address(grlm)));
        assertTrue(!core.isRateLimitedMinter(address(psm)));
        assertTrue(core.isRateLimitedRedeemer(address(psm)));
        assertTrue(core.isPCVController(address(psm)));

        assertEq(address(core.globalRateLimitedMinter()), address(grlm));
        assertEq(
            vso.monthlyChangeRateBasisPoints(),
            monthlyChangeRateBasisPoints
        );
        assertEq(address(opt.scalingPriceOracle()), address(vso));

        assertEq(psm.floor(), voltFloorPrice);
        assertEq(psm.ceiling(), voltCeilingPrice);
        assertEq(address(psm.pcvDeposit()), address(pcvDeposit));
        assertEq(psm.decimalsNormalizer(), 0);
        assertEq(address(psm.underlyingToken()), address(dai));

        assertEq(
            address(psm.underlyingToken()),
            address(custodialPsm.underlyingToken())
        );
        assertEq(psm.decimalsNormalizer(), custodialPsm.decimalsNormalizer());
        assertEq(psm.ceiling(), custodialPsm.ceiling());
        assertEq(psm.floor(), custodialPsm.floor());
    }

    /// @notice PSM is set up correctly and redeem view function is working
    function testGetRedeemAmountOut(uint128 amountVoltIn) public {
        uint256 currentPegPrice = opt.getCurrentOraclePrice();
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
        uint256 currentPegPrice = opt.getCurrentOraclePrice();
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
        uint256 currentPegPrice = opt.getCurrentOraclePrice();
        uint256 amountOut = (amountVoltIn * currentPegPrice) / 1e18;

        assertApproxEq(
            psm.getRedeemAmountOut(amountVoltIn).toInt256(),
            amountOut.toInt256(),
            0
        );
        assertEq(
            psm.getRedeemAmountOut(amountVoltIn).toInt256(),
            custodialPsm.getRedeemAmountOut(amountVoltIn).toInt256()
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

        {
            uint256 voltBalance = volt.balanceOf(address(this));
            uint256 underlyingAmountOut = psm.getRedeemAmountOut(voltBalance);
            uint256 userStartingUnderlyingBalance = dai.balanceOf(
                address(this)
            );
            uint256 depositStartingUnderlyingBalance = pcvDeposit.balance();
            amountOut = underlyingAmountOut;

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
                depositStartingUnderlyingBalance -
                    depositEndingUnderlyingBalance,
                underlyingAmountOut
            );

            assertEq(bufferAfterRedeem, grlm.bufferCap());
            assertEq(bufferAfterRedeem, grlm.buffer());
            assertEq(
                userEndingUnderlyingBalance - underlyingAmountOut,
                userStartingUnderlyingBalance
            );
            assertEq(volt.balanceOf(address(psm)), 0);
        }
        {
            uint256 voltBalance = volt.balanceOf(address(this));
            uint256 underlyingAmountOut = custodialPsm.getRedeemAmountOut(
                voltBalance
            );
            uint256 userStartingUnderlyingBalance = dai.balanceOf(
                address(this)
            );
            uint256 depositStartingUnderlyingBalance = custodialPsm.balance();

            volt.approve(address(psm), voltBalance);
            assertEq(
                underlyingAmountOut,
                custodialPsm.redeem(
                    address(this),
                    voltBalance,
                    underlyingAmountOut
                )
            );

            uint256 depositEndingUnderlyingBalance = custodialPsm.balance();
            uint256 userEndingUnderlyingBalance = dai.balanceOf(address(this));
            uint256 bufferAfterRedeem = grlm.buffer();

            uint256 endingBalance = dai.balanceOf(address(this));

            assertEq(endingBalance, underlyingAmountOut);

            assertEq(
                depositStartingUnderlyingBalance -
                    depositEndingUnderlyingBalance,
                underlyingAmountOut
            );

            assertEq(bufferAfterRedeem, grlm.bufferCap());
            assertEq(bufferAfterRedeem, grlm.buffer());
            assertEq(
                userEndingUnderlyingBalance - underlyingAmountOut,
                userStartingUnderlyingBalance
            );
            assertEq(
                userEndingUnderlyingBalance - userStartingUnderlyingBalance,
                amountOut
            );
            assertEq(volt.balanceOf(address(psm)), 0);
            assertEq(amountOut, underlyingAmountOut);
        }
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

        uint128 currentPrice = uint128(opt.getCurrentOraclePrice());
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
        IPCVDeposit newDeposit = IPCVDeposit(
            address(new MockPCVDepositV3(coreAddress, address(dai)))
        );
        vm.expectEmit(true, true, false, true, address(psm));
        emit PCVDepositUpdate(pcvDeposit, newDeposit);
        vm.prank(addresses.governorAddress);
        psm.setPCVDeposit(newDeposit);

        assertEq(address(psm.pcvDeposit()), address(newDeposit));
    }

    function testSetPCVDepositGovernorFailsMismatchUnderlyingToken() public {
        IPCVDeposit newDeposit = IPCVDeposit(
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
        psm.setPCVDeposit(IPCVDeposit(address(0)));
    }

    function testSetOracleCeilingPriceNonGovernorFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        psm.setOracleCeilingPrice(100);
    }
}