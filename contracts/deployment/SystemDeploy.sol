// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Test} from "../../forge-std/src/Test.sol";
import {CoreV2} from "../core/CoreV2.sol";
import {Deviation} from "../utils/Deviation.sol";
import {VoltRoles} from "../core/VoltRoles.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {PCVGuardian} from "../pcv/PCVGuardian.sol";
import {MockCoreRefV2} from "../mock/MockCoreRefV2.sol";
import {ERC20Allocator} from "../pcv/utils/ERC20Allocator.sol";
import {NonCustodialPSM} from "../peg/NonCustodialPSM.sol";
import {VoltSystemOracle} from "../oracle/VoltSystemOracle.sol";
import {MainnetAddresses} from "../test/integration/fixtures/MainnetAddresses.sol";
import {CompoundPCVRouter} from "../pcv/compound/CompoundPCVRouter.sol";
import {PegStabilityModule} from "../peg/PegStabilityModule.sol";
import {IScalingPriceOracle} from "../oracle/IScalingPriceOracle.sol";
import {IPCVDeposit, PCVDeposit} from "../pcv/PCVDeposit.sol";
import {MorphoCompoundPCVDeposit} from "../pcv/morpho/MorphoCompoundPCVDeposit.sol";
import {TestAddresses as addresses} from "../test/unit/utils/TestAddresses.sol";
import {IGlobalRateLimitedMinter, GlobalRateLimitedMinter} from "../limiter/GlobalRateLimitedMinter.sol";
import {IGlobalSystemExitRateLimiter, GlobalSystemExitRateLimiter} from "../limiter/GlobalSystemExitRateLimiter.sol";
import {getCoreV2, getVoltAddresses, VoltAddresses} from "../test/unit/utils/Fixtures.sol";

import "hardhat/console.sol";

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
/// 10. compound pcv router

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
contract SystemDeploy {
    using SafeCast for *;

    VoltAddresses public guardianAddresses = getVoltAddresses();

    CoreV2 private core;

    PegStabilityModule private daipsm;
    PegStabilityModule private usdcpsm;

    NonCustodialPSM private usdcNonCustodialPsm;
    NonCustodialPSM private daiNonCustodialPsm;

    MorphoCompoundPCVDeposit private daiPcvDeposit;
    MorphoCompoundPCVDeposit private usdcPcvDeposit;

    PCVGuardian private pcvGuardian;
    ERC20Allocator private allocator;
    CompoundPCVRouter private router;
    VoltSystemOracle private vso;
    TimelockController public timelockController;
    GlobalRateLimitedMinter public grlm;
    GlobalSystemExitRateLimiter public gserl;
    address private coreAddress;

    IERC20 private usdc;
    IERC20 private dai = IERC20(MainnetAddresses.DAI);
    IERC20 private volt = IERC20(MainnetAddresses.USDC);

    uint256 public constant timelockDelay = 600;
    uint248 public constant usdcTargetBalance = 10_000e6;
    uint248 public constant daiTargetBalance = 10_000e18;
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

    uint256 public constant startPrice = 1.05e18;
    uint256 public constant startTime = 1_000;
    uint256 public constant monthlyChangeRateBasisPoints = 100;

    address public voltAddress; /// TODO change this

    function setUp() public {
        core = new CoreV2(voltAddress);
        volt = IERC20(address(core.volt()));
        coreAddress = address(core);

        vso = new VoltSystemOracle(
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
        gserl = new GlobalSystemExitRateLimiter(
            coreAddress,
            maxRateLimitPerSecond,
            rateLimitPerSecond,
            bufferCap
        );

        usdcpsm = new PegStabilityModule(
            coreAddress,
            address(vso),
            address(0),
            -12,
            false,
            usdc,
            voltFloorPriceUsdc,
            voltCeilingPriceUsdc
        );

        daipsm = new PegStabilityModule(
            coreAddress,
            address(vso),
            address(0),
            0,
            false,
            dai,
            voltFloorPriceDai,
            voltCeilingPriceDai
        );

        daiPcvDeposit = new MorphoCompoundPCVDeposit(
            coreAddress,
            MainnetAddresses.CDAI,
            address(dai),
            MainnetAddresses.MORPHO,
            MainnetAddresses.MORPHO_LENS
        );
        usdcPcvDeposit = new MorphoCompoundPCVDeposit(
            coreAddress,
            MainnetAddresses.CUSDC,
            address(usdc),
            MainnetAddresses.MORPHO,
            MainnetAddresses.MORPHO_LENS
        );

        usdcNonCustodialPsm = new NonCustodialPSM(
            coreAddress,
            address(vso),
            address(0),
            -12,
            false,
            usdc,
            voltFloorPriceUsdc,
            voltCeilingPriceUsdc,
            IPCVDeposit(address(usdcPcvDeposit))
        );
        daiNonCustodialPsm = new NonCustodialPSM(
            coreAddress,
            address(vso),
            address(0),
            0,
            false,
            dai,
            voltFloorPriceDai,
            voltCeilingPriceDai,
            IPCVDeposit(address(daiPcvDeposit))
        );

        address[] memory executorAddresses = new address[](4);
        executorAddresses[0] = MainnetAddresses.EOA_1;
        executorAddresses[1] = MainnetAddresses.EOA_2;
        executorAddresses[2] = MainnetAddresses.EOA_3;
        executorAddresses[3] = MainnetAddresses.EOA_4;

        address[] memory proposerCancellerAddresses = new address[](1);
        proposerCancellerAddresses[0] = MainnetAddresses.GOVERNOR;

        timelockController = new TimelockController(
            timelockDelay,
            proposerCancellerAddresses,
            executorAddresses
        );

        address[] memory toWhitelist = new address[](4);
        toWhitelist[0] = address(daiPcvDeposit);
        toWhitelist[1] = address(usdcPcvDeposit);
        toWhitelist[2] = address(usdcpsm);
        toWhitelist[3] = address(daipsm);

        pcvGuardian = new PCVGuardian(
            coreAddress,
            address(timelockController),
            toWhitelist
        );
        allocator = new ERC20Allocator(coreAddress);
        router = new CompoundPCVRouter(
            coreAddress,
            PCVDeposit(address(daiPcvDeposit)),
            PCVDeposit(address(usdcPcvDeposit))
        );
    }

    function roleSetup(address deployer) public {
        core.grantGovernor(address(timelockController));

        core.grantPCVController(address(pcvGuardian));
        core.grantPCVController(address(router));
        core.grantPCVController(address(allocator));

        core.grantPCVGuard(MainnetAddresses.EOA_1);
        core.grantPCVGuard(MainnetAddresses.EOA_2);
        core.grantPCVGuard(MainnetAddresses.EOA_3);
        core.grantPCVGuard(MainnetAddresses.EOA_4);

        core.grantGuardian(address(pcvGuardian));

        core.grantRateLimitedMinter(address(daipsm));
        core.grantRateLimitedMinter(address(usdcpsm));

        core.grantRateLimitedRedeemer(address(daipsm));
        core.grantRateLimitedRedeemer(address(usdcpsm));
        core.grantRateLimitedRedeemer(address(daiNonCustodialPsm));
        core.grantRateLimitedRedeemer(address(usdcNonCustodialPsm));

        core.grantRateLimitedReplenisher(address(allocator));
        core.grantRateLimitedDepleter(address(daiNonCustodialPsm));
        core.grantRateLimitedDepleter(address(usdcNonCustodialPsm));
        core.grantRateLimitedDepleter(address(allocator));

        core.grantLocker(address(allocator));
        core.grantLocker(address(daipsm));
        core.grantLocker(address(usdcpsm));
        core.grantLocker(address(grlm));
        core.grantLocker(address(gserl));

        core.grantMinter(address(grlm));
        core.setGlobalRateLimitedMinter(
            IGlobalRateLimitedMinter(address(grlm))
        );
        core.setGlobalSystemExitRateLimiter(
            IGlobalSystemExitRateLimiter(address(gserl))
        );

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

        allocator.connectDeposit(address(usdcpsm), address(usdcPcvDeposit));
        allocator.connectDeposit(address(daipsm), address(daiPcvDeposit));

        core.revokeGovernor(deployer); /// remove governor from deployer

        timelockController.renounceRole(
            timelockController.TIMELOCK_ADMIN_ROLE(),
            address(this)
        );
    }
}
