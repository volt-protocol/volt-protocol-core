// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Test} from "@forge-std/Test.sol";
import {ICoreV2} from "@voltprotocol/core/ICoreV2.sol";
import {Deviation} from "@test/unit/utils/Deviation.sol";
import {VoltRoles} from "@voltprotocol/core/VoltRoles.sol";
import {MockERC20} from "@test/mock/MockERC20.sol";
import {PCVDeposit} from "@voltprotocol/pcv/PCVDeposit.sol";
import {SystemEntry} from "@voltprotocol/entry/SystemEntry.sol";
import {IPCVDepositBalances} from "@voltprotocol/pcv/IPCVDepositBalances.sol";
import {PCVGuardian} from "@voltprotocol/pcv/PCVGuardian.sol";
import {MockCoreRefV2} from "@test/mock/MockCoreRefV2.sol";
import {ERC20Allocator} from "@voltprotocol/pcv/ERC20Allocator.sol";
import {GenericCallMock} from "@test/mock/GenericCallMock.sol";
import {MockPCVDepositV2} from "@test/mock/MockPCVDepositV2.sol";
import {VoltSystemOracle} from "@voltprotocol/oracle/VoltSystemOracle.sol";
import {PegStabilityModule} from "@voltprotocol/peg/PegStabilityModule.sol";
import {MorphoCompoundPCVDeposit} from "@voltprotocol/pcv/morpho/MorphoCompoundPCVDeposit.sol";
import {TestAddresses as addresses} from "@test/unit/utils/TestAddresses.sol";
import {getCoreV2, getVoltAddresses, VoltAddresses} from "@test/unit/utils/Fixtures.sol";
import {IGlobalReentrancyLock, GlobalReentrancyLock} from "@voltprotocol/core/GlobalReentrancyLock.sol";
import {IGlobalRateLimitedMinter, GlobalRateLimitedMinter} from "@voltprotocol/rate-limits/GlobalRateLimitedMinter.sol";

/// deployment steps
/// 1. core v2
/// 2. Volt system oracle
/// 3. oracle pass through
/// 4. peg stability module dai
/// 5. peg stability module usdc
/// 6. pcv deposit dai
/// 7. pcv deposit usdc
/// 8. pcv guardian
/// 9. erc20 allocator

/// setup steps
/// 1. grant pcv guardian pcv controller role
/// 2. grant erc20 allocator pcv controller role
/// 3. grant pcv guardian guardian role
/// 4. grant pcv guard role to EOA's
/// 5. configure timelock as owner of oracle pass through
/// 6. revoke timelock admin rights from deployer
/// 7. grant timelock governor
/// 8. connect pcv deposits to psm in allocator

/// PSM target balance is 10k cash for both deposits

/// test steps
/// 1. do swaps in psm
/// 2. do emergency action to pull funds
/// 3. do sweep to pull funds
/// 4. do pcv guardian withdraw as EOA

interface IERC20Mintable is IERC20 {
    function mint(address, uint256) external;
}

contract SystemUnitTest is Test {
    using SafeCast for *;
    VoltAddresses public guardianAddresses = getVoltAddresses();

    ICoreV2 private core;
    SystemEntry private entry;
    PegStabilityModule private daipsm;
    PegStabilityModule private usdcpsm;
    MockPCVDepositV2 private pcvDepositDai;
    MockPCVDepositV2 private pcvDepositUsdc;
    PCVGuardian private pcvGuardian;
    ERC20Allocator private allocator;
    VoltSystemOracle private oracle;
    TimelockController private timelockController;
    GlobalRateLimitedMinter private grlm;
    IGlobalReentrancyLock private lock;

    address private voltAddress;
    address private coreAddress;
    IERC20Mintable private usdc;
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

    uint128 public constant voltFloorPriceDai = 1.05e18; /// 1 volt for 1.05 dai is the minimum price
    uint128 public constant voltCeilingPriceDai = 1.1e18; /// 1 volt for 1.1 dai is the max allowable price

    uint128 public constant voltFloorPriceUsdc = 1.05e6; /// 1 volt for 1.05 usdc is the min price
    uint128 public constant voltCeilingPriceUsdc = 1.1e6; /// 1 volt for 1.1 usdc is the max price

    /// ---------- ORACLE PARAMS ----------

    uint200 public constant startPrice = 1.05e18;
    uint40 public constant startTime = 1_000;
    uint16 public constant monthlyChangeRateBasisPoints = 100;

    function setUp() public {
        vm.warp(startTime); /// warp past 0
        core = getCoreV2();
        entry = new SystemEntry(address(core));
        volt = IERC20Mintable(address(core.volt()));
        voltAddress = address(volt);
        coreAddress = address(core);
        lock = IGlobalReentrancyLock(
            address(new GlobalReentrancyLock(coreAddress))
        );
        dai = IERC20Mintable(address(new MockERC20()));
        usdc = IERC20Mintable(address(new MockERC20()));
        oracle = new VoltSystemOracle(
            address(core),
            monthlyChangeRateBasisPoints,
            startTime,
            startPrice
        );
        grlm = new GlobalRateLimitedMinter(
            coreAddress,
            maxRateLimitPerSecondMinting,
            rateLimitPerSecondMinting,
            bufferCapMinting
        );

        usdcpsm = new PegStabilityModule(
            coreAddress,
            address(oracle),
            address(0),
            -12,
            false,
            usdc,
            voltFloorPriceUsdc,
            voltCeilingPriceUsdc
        );

        daipsm = new PegStabilityModule(
            coreAddress,
            address(oracle),
            address(0),
            0,
            false,
            dai,
            voltFloorPriceDai,
            voltCeilingPriceDai
        );

        pcvDepositDai = new MockPCVDepositV2(coreAddress, address(dai), 100, 0);
        pcvDepositUsdc = new MockPCVDepositV2(
            coreAddress,
            address(usdc),
            100,
            0
        );

        address[] memory proposerCancellerAddresses = new address[](3);
        proposerCancellerAddresses[0] = guardianAddresses.pcvGuardAddress1;
        proposerCancellerAddresses[1] = guardianAddresses.pcvGuardAddress2;
        proposerCancellerAddresses[2] = guardianAddresses.executorAddress;

        address[] memory executorAddresses = new address[](2);
        executorAddresses[0] = addresses.governorAddress;
        executorAddresses[1] = addresses.voltGovernorAddress;

        timelockController = new TimelockController(
            timelockDelay,
            proposerCancellerAddresses,
            executorAddresses
        );

        address[] memory toWhitelist = new address[](4);
        toWhitelist[0] = address(pcvDepositDai);
        toWhitelist[1] = address(pcvDepositUsdc);
        toWhitelist[2] = address(usdcpsm);
        toWhitelist[3] = address(daipsm);

        pcvGuardian = new PCVGuardian(
            coreAddress,
            address(timelockController),
            toWhitelist
        );
        allocator = new ERC20Allocator(coreAddress);

        timelockController.renounceRole(
            timelockController.TIMELOCK_ADMIN_ROLE(),
            address(this)
        );

        vm.startPrank(addresses.governorAddress);

        core.grantPCVController(address(pcvGuardian));
        core.grantPCVController(address(allocator));

        core.grantPCVGuard(addresses.userAddress);
        core.grantPCVGuard(addresses.secondUserAddress);

        core.grantGuardian(address(pcvGuardian));

        core.grantGovernor(address(timelockController));

        core.grantMinter(address(grlm));
        core.grantRateLimitedMinter(address(daipsm));
        core.grantRateLimitedMinter(address(usdcpsm));
        core.grantRateLimitedRedeemer(address(daipsm));
        core.grantRateLimitedRedeemer(address(usdcpsm));

        core.grantLocker(address(pcvGuardian));
        core.grantLocker(address(allocator));
        core.grantLocker(address(usdcpsm));
        core.grantLocker(address(daipsm));
        core.grantLocker(address(entry));
        core.grantLocker(address(grlm));

        core.setGlobalRateLimitedMinter(
            IGlobalRateLimitedMinter(address(grlm))
        );
        core.setGlobalReentrancyLock(lock);

        allocator.connectPSM(
            address(usdcpsm),
            usdcTargetBalance,
            usdcDecimalsNormalizer
        );
        allocator.connectPSM(
            address(daipsm),
            daiTargetBalance,
            daiDecimalsNormalizer
        );

        allocator.connectDeposit(address(usdcpsm), address(pcvDepositUsdc));
        allocator.connectDeposit(address(daipsm), address(pcvDepositDai));
        vm.stopPrank();

        /// top up contracts with tokens for testing
        dai.mint(address(daipsm), daiTargetBalance);
        usdc.mint(address(usdcpsm), usdcTargetBalance);
        dai.mint(address(pcvDepositDai), daiTargetBalance);
        usdc.mint(address(pcvDepositUsdc), usdcTargetBalance);

        vm.label(address(timelockController), "Timelock Controller");
        vm.label(address(entry), "entry");
        vm.label(address(daipsm), "daipsm");
        vm.label(address(usdcpsm), "usdcpsm");
        vm.label(address(pcvDepositDai), "pcvDepositDai");
        vm.label(address(pcvDepositUsdc), "pcvDepositUsdc");
        vm.label(address(this), "address this");
    }

    function testSetup() public {
        assertTrue(core.isLocker(address(usdcpsm)));
        assertTrue(core.isLocker(address(daipsm)));
        assertTrue(core.isLocker(address(allocator)));

        assertTrue(
            !timelockController.hasRole(
                timelockController.TIMELOCK_ADMIN_ROLE(),
                address(this)
            )
        );
        /// timelock has admin role of itself
        assertTrue(
            timelockController.hasRole(
                timelockController.TIMELOCK_ADMIN_ROLE(),
                address(timelockController)
            )
        );

        bytes32 cancellerRole = timelockController.CANCELLER_ROLE();
        assertTrue(
            timelockController.hasRole(
                cancellerRole,
                guardianAddresses.pcvGuardAddress1
            )
        );
        assertTrue(
            timelockController.hasRole(
                cancellerRole,
                guardianAddresses.pcvGuardAddress2
            )
        );
        assertTrue(
            timelockController.hasRole(
                cancellerRole,
                guardianAddresses.executorAddress
            )
        );

        bytes32 proposerRole = timelockController.PROPOSER_ROLE();
        assertTrue(
            timelockController.hasRole(
                proposerRole,
                guardianAddresses.pcvGuardAddress1
            )
        );
        assertTrue(
            timelockController.hasRole(
                proposerRole,
                guardianAddresses.pcvGuardAddress2
            )
        );
        assertTrue(
            timelockController.hasRole(
                proposerRole,
                guardianAddresses.executorAddress
            )
        );

        bytes32 executorRole = timelockController.EXECUTOR_ROLE();
        assertTrue(
            timelockController.hasRole(executorRole, addresses.governorAddress)
        );
        assertTrue(
            timelockController.hasRole(
                executorRole,
                addresses.voltGovernorAddress
            )
        );

        assertTrue(core.isMinter(address(grlm)));
        assertTrue(core.isRateLimitedMinter(address(usdcpsm)));
        assertTrue(core.isRateLimitedMinter(address(daipsm)));

        assertEq(address(core.globalRateLimitedMinter()), address(grlm));

        assertTrue(pcvGuardian.isWhitelistAddress(address(pcvDepositDai)));
        assertTrue(pcvGuardian.isWhitelistAddress(address(pcvDepositUsdc)));
        assertTrue(pcvGuardian.isWhitelistAddress(address(usdcpsm)));
        assertTrue(pcvGuardian.isWhitelistAddress(address(daipsm)));

        assertEq(pcvGuardian.safeAddress(), address(timelockController));
        assertEq(
            oracle.monthlyChangeRateBasisPoints(),
            monthlyChangeRateBasisPoints
        );

        {
            (
                address psmToken,
                uint248 psmTargetBalance,
                int8 decimalsNormalizer
            ) = allocator.allPSMs(address(usdcpsm));
            address psmAddress = allocator.pcvDepositToPSM(
                address(pcvDepositUsdc)
            );
            assertEq(psmTargetBalance, usdcTargetBalance);
            assertEq(decimalsNormalizer, usdcDecimalsNormalizer);
            assertEq(psmAddress, address(usdcpsm));
            assertEq(psmToken, address(usdc));
        }
        {
            (
                address psmToken,
                uint248 psmTargetBalance,
                int8 decimalsNormalizer
            ) = allocator.allPSMs(address(daipsm));
            address psmAddress = allocator.pcvDepositToPSM(
                address(pcvDepositDai)
            );
            assertEq(psmTargetBalance, daiTargetBalance);
            assertEq(decimalsNormalizer, daiDecimalsNormalizer);
            assertEq(psmAddress, address(daipsm));
            assertEq(psmToken, address(dai));
        }

        assertTrue(core.isPCVController(address(pcvGuardian)));
        assertTrue(core.isPCVController(address(allocator)));

        assertTrue(core.isGovernor(address(timelockController)));
        assertTrue(core.isGovernor(address(core)));

        assertTrue(core.isPCVGuard(addresses.userAddress));
        assertTrue(core.isPCVGuard(addresses.secondUserAddress));

        assertTrue(core.isGuardian(address(pcvGuardian)));
    }

    function testPCVGuardWithdrawAllToSafeAddress() public {
        vm.startPrank(addresses.userAddress);

        pcvGuardian.withdrawAllToSafeAddress(address(daipsm));
        pcvGuardian.withdrawAllToSafeAddress(address(usdcpsm));
        pcvGuardian.withdrawAllToSafeAddress(address(pcvDepositDai));
        pcvGuardian.withdrawAllToSafeAddress(address(pcvDepositUsdc));

        vm.stopPrank();

        assertEq(
            dai.balanceOf(address(timelockController)),
            daiTargetBalance * 2
        );
        assertEq(
            usdc.balanceOf(address(timelockController)),
            usdcTargetBalance * 2
        );

        assertEq(dai.balanceOf(address(pcvDepositDai)), 0);
        assertEq(dai.balanceOf(address(daipsm)), 0);

        assertEq(usdc.balanceOf(address(pcvDepositUsdc)), 0);
        assertEq(usdc.balanceOf(address(usdcpsm)), 0);
    }

    function testMintRedeemSamePriceLosesMoneyDai(uint128 mintAmount) public {
        vm.assume(mintAmount != 0);

        uint256 voltAmountOut = daipsm.getMintAmountOut(mintAmount);

        vm.assume(voltAmountOut <= grlm.buffer());

        uint256 startingBuffer = grlm.buffer();
        assertEq(volt.balanceOf(address(this)), 0);
        dai.mint(address(this), mintAmount);
        uint256 startingBalance = dai.balanceOf(address(this));

        dai.approve(address(daipsm), mintAmount);
        daipsm.mint(address(this), mintAmount, voltAmountOut);

        uint256 bufferAfterMint = grlm.buffer();

        assertEq(startingBuffer - voltAmountOut, bufferAfterMint);

        uint256 voltBalance = volt.balanceOf(address(this));
        uint256 underlyingAmountOut = daipsm.getRedeemAmountOut(voltBalance);
        uint256 userStartingUnderlyingBalance = dai.balanceOf(address(this));

        volt.approve(address(daipsm), voltBalance);
        daipsm.redeem(address(this), voltBalance, underlyingAmountOut);

        uint256 userEndingUnderlyingBalance = dai.balanceOf(address(this));
        uint256 bufferAfterRedeem = grlm.buffer();

        uint256 endingBalance = dai.balanceOf(address(this));

        assertEq(bufferAfterRedeem - voltBalance, bufferAfterMint); /// assert buffer
        assertEq(
            userEndingUnderlyingBalance - underlyingAmountOut,
            userStartingUnderlyingBalance
        );
        assertTrue(startingBalance >= endingBalance);
        assertEq(volt.balanceOf(address(daipsm)), 0);
        assertEq(startingBuffer, bufferAfterRedeem);
    }

    function testMintRedeemSamePriceLosesOrBreaksEvenDaiNonFuzz() public {
        uint128 mintAmount = 1_000e18;

        uint256 voltAmountOut = daipsm.getMintAmountOut(mintAmount);
        volt.mint(address(daipsm), voltAmountOut);

        assertEq(volt.balanceOf(address(this)), 0);
        dai.mint(address(this), mintAmount);
        uint256 startingBalance = dai.balanceOf(address(this));

        dai.approve(address(daipsm), mintAmount);
        daipsm.mint(address(this), mintAmount, voltAmountOut);

        uint256 voltBalance = volt.balanceOf(address(this));
        volt.approve(address(daipsm), voltBalance);
        daipsm.redeem(address(this), voltBalance, 0);

        uint256 endingBalance = dai.balanceOf(address(this));

        assertTrue(startingBalance >= endingBalance);

        assertEq(volt.balanceOf(address(daipsm)), voltAmountOut);
    }

    function testMintRedeemSamePriceLosesOrBreaksEvenUsdc(
        uint80 mintAmount
    ) public {
        vm.assume(mintAmount != 0);

        uint256 voltAmountOut = usdcpsm.getMintAmountOut(mintAmount);
        vm.assume(voltAmountOut <= grlm.buffer()); /// avoid rate limit hit error

        assertEq(volt.balanceOf(address(this)), 0);
        usdc.mint(address(this), mintAmount);
        uint256 startingBalance = usdc.balanceOf(address(this));
        uint256 startingBuffer = grlm.buffer();

        usdc.approve(address(usdcpsm), mintAmount);
        usdcpsm.mint(address(this), mintAmount, voltAmountOut);

        uint256 bufferAfterMint = grlm.buffer();
        assertEq(bufferAfterMint + voltAmountOut, startingBuffer);

        uint256 voltBalance = volt.balanceOf(address(this));
        volt.approve(address(usdcpsm), voltBalance);
        usdcpsm.redeem(address(this), voltBalance, 0);

        uint256 bufferAfterRedeem = grlm.buffer();
        uint256 endingBalance = usdc.balanceOf(address(this));

        assertEq(bufferAfterRedeem, startingBuffer);
        assertTrue(startingBalance >= endingBalance);
        assertEq(volt.balanceOf(address(usdcpsm)), 0);
    }

    function _emergencyPause() private {
        vm.prank(addresses.governorAddress);
        lock.governanceEmergencyPause();

        assertEq(lock.lockLevel(), 2);
        assertTrue(lock.isLocked());
        assertTrue(!lock.isUnlocked());
    }

    function testPsmFailureOnSystemEmergencyPause() public {
        _emergencyPause();

        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        usdcpsm.mint(address(this), 0, 0);

        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        usdcpsm.redeem(address(this), 0, 0);

        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        daipsm.mint(address(this), 0, 0);

        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        daipsm.redeem(address(this), 0, 0);
    }

    function testAllocatorFailureOnSystemEmergencyPause() public {
        _emergencyPause();

        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        allocator.drip(address(pcvDepositDai));

        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        allocator.skim(address(pcvDepositDai));
    }

    function testPcvGuardianFailureOnSystemEmergencyPause() public {
        _emergencyPause();

        vm.prank(addresses.userAddress);
        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        pcvGuardian.withdrawAllERC20ToSafeAddress(
            address(pcvDepositDai),
            address(dai)
        );

        vm.prank(addresses.userAddress);
        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        pcvGuardian.withdrawERC20ToSafeAddress(
            address(pcvDepositDai),
            address(dai),
            0
        );

        vm.prank(addresses.userAddress);
        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        pcvGuardian.withdrawToSafeAddress(address(pcvDepositDai), 0);

        vm.prank(addresses.userAddress);
        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        pcvGuardian.withdrawAllToSafeAddress(address(pcvDepositDai));
    }

    function testReentrancyLockMaliciousExternalVenue() public {
        /// fake deposit
        GenericCallMock mock = new GenericCallMock();

        mock.setResponseToCall(
            address(0),
            "",
            abi.encode(usdc),
            IPCVDepositBalances.balanceReportedIn.selector
        );

        /// ctoken response
        mock.setResponseToCall(
            address(0),
            "",
            abi.encode(usdc),
            bytes4(keccak256("underlying()"))
        );

        /// morpho lens response
        mock.setResponseToCall(
            address(0),
            "",
            abi.encode(usdc),
            bytes4(keccak256("getCurrentSupplyBalanceInOf(address,address)"))
        );

        /// morpho response
        mock.setResponseToCall(
            address(0),
            "",
            "",
            bytes4(keccak256("supply(address,address,uint256)"))
        );

        MorphoCompoundPCVDeposit deposit = new MorphoCompoundPCVDeposit(
            address(core),
            address(mock),
            address(usdc),
            address(mock),
            address(mock)
        );

        vm.prank(addresses.governorAddress);
        core.grantLocker(address(deposit));

        /// call to morpo update indexes attempts reentry
        mock.setResponseToCall(
            address(entry),
            abi.encodeWithSignature("accrue(address)", address(deposit)),
            "",
            bytes4(keccak256("updateP2PIndexes(address)"))
        );

        vm.prank(addresses.governorAddress);
        allocator.connectDeposit(address(usdcpsm), address(deposit));

        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        entry.accrue(address(deposit));

        deal(address(usdc), address(deposit), 1);
        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        entry.deposit(address(deposit));
    }
}
