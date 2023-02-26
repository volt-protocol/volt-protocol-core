// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {console} from "@forge-std/console.sol";

import {Test} from "@forge-std/Test.sol";
import {ICoreV2} from "@voltprotocol/core/ICoreV2.sol";
import {Deviation} from "@test/unit/utils/Deviation.sol";
import {VoltRoles} from "@voltprotocol/core/VoltRoles.sol";
import {MockERC20} from "@test/mock/MockERC20.sol";
import {PCVRouter} from "@voltprotocol/pcv/PCVRouter.sol";
import {PCVOracle} from "@voltprotocol/oracle/PCVOracle.sol";
import {PCVDeposit} from "@voltprotocol/pcv/PCVDeposit.sol";
import {SystemEntry} from "@voltprotocol/entry/SystemEntry.sol";
import {PCVGuardian} from "@voltprotocol/pcv/PCVGuardian.sol";
import {MockCoreRefV2} from "@test/mock/MockCoreRefV2.sol";
import {GenericCallMock} from "@test/mock/GenericCallMock.sol";
import {MockPCVDepositV3} from "@test/mock/MockPCVDepositV3.sol";
import {VoltSystemOracle} from "@voltprotocol/oracle/VoltSystemOracle.sol";
import {IPCVDepositBalances} from "@voltprotocol/pcv/IPCVDepositBalances.sol";
import {ConstantPriceOracle} from "@voltprotocol/oracle/ConstantPriceOracle.sol";
import {MorphoCompoundPCVDeposit} from "@voltprotocol/pcv/morpho/MorphoCompoundPCVDeposit.sol";
import {TestAddresses as addresses} from "@test/unit/utils/TestAddresses.sol";
import {IGlobalReentrancyLock, GlobalReentrancyLock} from "@voltprotocol/core/GlobalReentrancyLock.sol";
import {IGlobalRateLimitedMinter, GlobalRateLimitedMinter} from "@voltprotocol/rate-limits/GlobalRateLimitedMinter.sol";
import {getCoreV2, getVoltAddresses, VoltAddresses, getVoltSystemOracle} from "@test/unit/utils/Fixtures.sol";

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

    ICoreV2 public core;
    SystemEntry public entry;
    MockPCVDepositV3 public pcvDepositDai;
    MockPCVDepositV3 public pcvDepositUsdc;
    PCVGuardian public pcvGuardian;
    VoltSystemOracle public oracle;
    TimelockController public timelockController;
    GlobalRateLimitedMinter public grlm;
    IGlobalReentrancyLock public lock;
    PCVRouter public pcvRouter;
    PCVOracle public pcvOracle;
    ConstantPriceOracle public daiConstantOracle;
    ConstantPriceOracle public usdcConstantOracle;

    address public voltAddress;
    address public coreAddress;
    IERC20Mintable public usdc;
    IERC20Mintable public dai;
    IERC20Mintable public volt;
    IERC20Mintable public vcon;

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

    /// ---------- PSM PARAMS ----------

    uint128 public constant voltFloorPriceDai = 1.05e18; /// 1 volt for 1.05 dai is the minimum price
    uint128 public constant voltCeilingPriceDai = 1.1e18; /// 1 volt for 1.1 dai is the max allowable price

    uint128 public constant voltFloorPriceUsdc = 1.05e6; /// 1 volt for 1.05 usdc is the min price
    uint128 public constant voltCeilingPriceUsdc = 1.1e6; /// 1 volt for 1.1 usdc is the max price

    /// ---------- ORACLE PARAMS ----------

    uint112 public constant startPrice = 1.05e18;
    uint112 public constant monthlyChangeRate = .01e18; /// 100 basis points
    uint32 public constant startTime = 1_000;

    function setUp() public virtual {
        vm.warp(startTime); /// warp past 0
        core = getCoreV2();
        entry = new SystemEntry(address(core));
        volt = IERC20Mintable(address(core.volt()));
        vcon = IERC20Mintable(address(core.vcon()));
        voltAddress = address(volt);
        coreAddress = address(core);
        lock = IGlobalReentrancyLock(
            address(new GlobalReentrancyLock(coreAddress))
        );
        dai = IERC20Mintable(address(new MockERC20()));
        usdc = IERC20Mintable(address(new MockERC20()));
        oracle = getVoltSystemOracle(
            address(core),
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

        pcvDepositDai = new MockPCVDepositV3(coreAddress, address(dai));
        pcvDepositUsdc = new MockPCVDepositV3(coreAddress, address(usdc));

        pcvRouter = new PCVRouter(coreAddress);

        pcvOracle = new PCVOracle(coreAddress);
        daiConstantOracle = new ConstantPriceOracle(coreAddress, 1e18);
        usdcConstantOracle = new ConstantPriceOracle(coreAddress, 1e30);

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

        address[] memory toWhitelist = new address[](2);
        toWhitelist[0] = address(pcvDepositDai);
        toWhitelist[1] = address(pcvDepositUsdc);

        pcvGuardian = new PCVGuardian(
            coreAddress,
            address(timelockController),
            toWhitelist
        );

        timelockController.renounceRole(
            timelockController.TIMELOCK_ADMIN_ROLE(),
            address(this)
        );

        vm.startPrank(addresses.governorAddress);

        core.grantPCVController(address(pcvGuardian));
        core.grantPCVController(address(pcvRouter));

        core.grantPCVGuard(addresses.userAddress);
        core.grantPCVGuard(addresses.secondUserAddress);

        core.grantGuardian(address(pcvGuardian));

        core.grantGovernor(address(timelockController));

        core.grantMinter(address(grlm));

        core.grantLocker(address(pcvDepositUsdc));
        core.grantLocker(address(pcvDepositDai));
        core.grantLocker(address(pcvGuardian));
        core.grantLocker(address(pcvOracle));
        core.grantLocker(address(entry));
        core.grantLocker(address(grlm));

        core.setGlobalRateLimitedMinter(
            IGlobalRateLimitedMinter(address(grlm))
        );
        core.setGlobalReentrancyLock(lock);

        /// top up contracts with tokens for testing
        /// if done after the setting of pcv oracle, balances will be incorrect unless deposit is called
        dai.mint(address(pcvDepositDai), daiTargetBalance);
        usdc.mint(address(pcvDepositUsdc), usdcTargetBalance);

        /// Configure PCV Oracle
        address[] memory venues = new address[](2);
        venues[0] = address(pcvDepositDai);
        venues[1] = address(pcvDepositUsdc);

        address[] memory oracles = new address[](2);
        oracles[0] = address(daiConstantOracle);
        oracles[1] = address(usdcConstantOracle);

        pcvOracle.addVenues(venues, oracles);

        core.setPCVOracle(pcvOracle);

        core.createRole(VoltRoles.PCV_DEPOSIT, VoltRoles.GOVERNOR);
        core.grantRole(VoltRoles.PCV_DEPOSIT, address(pcvDepositDai));
        core.grantRole(VoltRoles.PCV_DEPOSIT, address(pcvDepositUsdc));

        vm.stopPrank();

        vm.label(address(timelockController), "Timelock Controller");
        vm.label(address(entry), "entry");
        vm.label(address(pcvDepositDai), "pcvDepositDai");
        vm.label(address(pcvDepositUsdc), "pcvDepositUsdc");
        vm.label(address(this), "address this");
        vm.label(address(dai), "DAI");
        vm.label(address(usdc), "USDC");
    }

    function testSetup() public {
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

        assertEq(address(core.globalRateLimitedMinter()), address(grlm));

        assertTrue(pcvGuardian.isWhitelistAddress(address(pcvDepositDai)));
        assertTrue(pcvGuardian.isWhitelistAddress(address(pcvDepositUsdc)));

        assertEq(pcvGuardian.safeAddress(), address(timelockController));
        assertEq(oracle.monthlyChangeRate(), monthlyChangeRate);

        assertTrue(core.isPCVController(address(pcvGuardian)));

        assertTrue(core.isGovernor(address(timelockController)));
        assertTrue(core.isGovernor(address(core)));

        assertTrue(core.isPCVGuard(addresses.userAddress));
        assertTrue(core.isPCVGuard(addresses.secondUserAddress));

        assertTrue(core.isGuardian(address(pcvGuardian)));

        assertTrue(pcvOracle.isVenue(address(pcvDepositDai)));
        assertTrue(pcvOracle.isVenue(address(pcvDepositUsdc)));
    }

    function testPCVGuardWithdrawAllToSafeAddress() public {
        entry.deposit(address(pcvDepositDai));
        entry.deposit(address(pcvDepositUsdc));

        vm.startPrank(addresses.userAddress);

        pcvGuardian.withdrawAllToSafeAddress(address(pcvDepositDai));
        pcvGuardian.withdrawAllToSafeAddress(address(pcvDepositUsdc));

        vm.stopPrank();

        assertEq(dai.balanceOf(address(timelockController)), daiTargetBalance);
        assertEq(
            usdc.balanceOf(address(timelockController)),
            usdcTargetBalance
        );

        assertEq(dai.balanceOf(address(pcvDepositDai)), 0);
        assertEq(usdc.balanceOf(address(pcvDepositUsdc)), 0);
    }

    function _emergencyPause() private {
        vm.prank(addresses.governorAddress);
        lock.governanceEmergencyPause();

        assertEq(lock.lockLevel(), 2);
        assertTrue(lock.isLocked());
        assertTrue(!lock.isUnlocked());
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
            address(0),
            address(mock),
            address(mock)
        );
        vm.label(address(deposit), "Malicious Morpho Compound PCV Deposit");

        /// Configure PCV Oracle
        address[] memory venues = new address[](1);
        venues[0] = address(deposit);

        address[] memory oracles = new address[](1);
        oracles[0] = address(usdcConstantOracle);

        /// call to morpo update indexes does nothing at first
        mock.setResponseToCall(
            address(0),
            "",
            "",
            bytes4(keccak256("updateP2PIndexes(address)"))
        );

        /// call to accrue returns 0
        mock.setResponseToCall(
            address(0),
            "",
            abi.encode(0),
            bytes4(keccak256("accrue(address)"))
        );

        /// call to getCurrentSupplyBalanceInOf returns 0
        mock.setResponseToCall(
            address(0),
            "",
            abi.encode(0, 0, 0),
            bytes4(keccak256("getCurrentSupplyBalanceInOf(address,address)"))
        );

        vm.startPrank(addresses.governorAddress);
        core.grantLocker(address(deposit));
        core.createRole(VoltRoles.PCV_DEPOSIT, VoltRoles.GOVERNOR);
        core.grantRole(VoltRoles.PCV_DEPOSIT, address(deposit));
        pcvOracle.addVenues(venues, oracles);
        vm.stopPrank();

        /// call to morpo update indexes attempts reentry
        mock.setResponseToCall(
            address(entry),
            abi.encodeWithSignature("accrue(address)", address(deposit)),
            "",
            bytes4(keccak256("updateP2PIndexes(address)"))
        );

        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        entry.accrue(address(deposit));

        deal(address(usdc), address(deposit), 1);
        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        entry.deposit(address(deposit));
    }
}
