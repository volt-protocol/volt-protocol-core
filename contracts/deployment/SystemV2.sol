// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Test} from "../../forge-std/src/Test.sol";
import {CoreV2} from "../core/CoreV2.sol";
import {Deviation} from "../utils/Deviation.sol";
import {SystemEntry} from "../entry/SystemEntry.sol";
import {IVolt} from "../volt/IVolt.sol";
import {VoltV2} from "../volt/VoltV2.sol";
import {VoltRoles} from "../core/VoltRoles.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {PCVGuardian} from "../pcv/PCVGuardian.sol";
import {PCVRouter} from "../pcv/PCVRouter.sol";
import {MockCoreRefV2} from "../mock/MockCoreRefV2.sol";
import {ERC20Allocator} from "../pcv/utils/ERC20Allocator.sol";
import {NonCustodialPSM} from "../peg/NonCustodialPSM.sol";
import {VoltSystemOracle} from "../oracle/VoltSystemOracle.sol";
import {ConstantPriceOracle} from "../oracle/ConstantPriceOracle.sol";
import {PCVOracle} from "../oracle/PCVOracle.sol";
import {IPCVOracle} from "../oracle/IPCVOracle.sol";
import {MainnetAddresses} from "../test/integration/fixtures/MainnetAddresses.sol";
import {MakerPCVSwapper} from "../pcv/maker/MakerPCVSwapper.sol";
import {PegStabilityModule} from "../peg/PegStabilityModule.sol";
import {IPCVDeposit, PCVDeposit} from "../pcv/PCVDeposit.sol";
import {MorphoCompoundPCVDeposit} from "../pcv/morpho/MorphoCompoundPCVDeposit.sol";
import {IGlobalRateLimitedMinter, GlobalRateLimitedMinter} from "../limiter/GlobalRateLimitedMinter.sol";
import {IGlobalSystemExitRateLimiter, GlobalSystemExitRateLimiter} from "../limiter/GlobalSystemExitRateLimiter.sol";

contract SystemV2 {
    using SafeCast for *;

    /// External
    IERC20 public usdc = IERC20(MainnetAddresses.USDC);
    IERC20 public dai = IERC20(MainnetAddresses.DAI);
    IERC20 public voltV1 = IERC20(0x559eBC30b0E58a45Cc9fF573f77EF1e5eb1b3E18);

    /// Core
    VoltV2 public volt;
    CoreV2 public core;
    TimelockController public timelockController;
    GlobalRateLimitedMinter public grlm;
    GlobalSystemExitRateLimiter public gserl;

    /// VOLT rate
    VoltSystemOracle public vso;

    /// PCV Deposits
    MorphoCompoundPCVDeposit public morphoDaiPCVDeposit;
    MorphoCompoundPCVDeposit public morphoUsdcPCVDeposit;

    /// Peg Stability
    PegStabilityModule public daipsm;
    PegStabilityModule public usdcpsm;
    NonCustodialPSM public usdcNonCustodialPsm;
    NonCustodialPSM public daiNonCustodialPsm;
    ERC20Allocator public allocator;

    /// PCV Movement
    SystemEntry public systemEntry;
    MakerPCVSwapper public pcvSwapperMaker;
    PCVGuardian public pcvGuardian;
    PCVRouter public pcvRouter;

    /// Accounting
    PCVOracle public pcvOracle;
    ConstantPriceOracle public daiConstantOracle;
    ConstantPriceOracle public usdcConstantOracle;

    /// Parameters
    uint256 public constant TIMELOCK_DELAY = 600;

    /// ---------- RATE LIMITED MINTER PARAMS ----------

    /// maximum rate limit per second is 100 VOLT
    uint256 public constant MAX_RATE_LIMIT_PER_SECOND_MINTING = 100e18;

    /// replenish 500k VOLT per day (5.787 VOLT per second)
    uint128 public constant RATE_LIMIT_PER_SECOND_MINTING = 5787037037037037000;

    /// buffer cap of 1.5m VOLT
    uint128 public constant BUFFER_CAP_MINTING = 1_500_000e18;

    /// ---------- RATE LIMITED MINTER PARAMS ----------

    /// maximum rate limit per second is $100
    uint256 public constant MAX_RATE_LIMIT_PER_SECOND_EXITING = 100e18;

    /// replenish 500k VOLT per day ($5.787 dollars per second)
    uint128 public constant RATE_LIMIT_PER_SECOND_EXIT = 5787037037037037000;

    /// buffer cap of 1.5m VOLT
    uint128 public constant BUFFER_CAP_EXITING = 500_000e18;

    /// ---------- ALLOCATOR PARAMS ----------

    uint256 public constant ALLOCATOR_MAX_RATE_LIMIT_PER_SECOND = 1_000e18; /// 1k volt per second
    uint128 public constant ALLOCATOR_RATE_LIMIT_PER_SECOND = 10e18; /// 10 volt per second
    uint128 public constant ALLOCATOR_BUFFER_CAP = 1_000_000e18; /// buffer cap is 1m volt

    /// ---------- PSM PARAMS ----------

    uint128 public constant VOLT_FLOOR_PRICE_USDC = 1.05e6;
    uint128 public constant VOLT_CEILING_PRICE_USDC = 1.10e6;
    uint128 public constant VOLT_FLOOR_PRICE_DAI = 1.05e18;
    uint128 public constant VOLT_CEILING_PRICE_DAI = 1.10e18;
    uint248 public constant USDC_TARGET_BALANCE = 10_000e6;
    uint248 public constant DAI_TARGET_BALANCE = 10_000e18;
    int8 public constant USDC_DECIMALS_NORMALIZER = 12;
    int8 public constant DAI_DECIMALS_NORMALIZER = 0;

    /// ---------- ORACLE PARAMS ----------

    uint40 public constant VOLT_APR_START_TIME = 1672531200; /// 2023-01-01
    uint200 public constant VOLT_START_PRICE = 1.05e18;
    uint16 public constant VOLT_MONTHLY_BASIS_POINTS = 18;

    function deploy() public {
        /// Core
        core = new CoreV2(address(voltV1));

        volt = new VoltV2(address(core));

        /// all addresses will be able to execute
        address[] memory executorAddresses = new address[](0);

        address[] memory proposerCancellerAddresses = new address[](1);
        proposerCancellerAddresses[0] = MainnetAddresses.GOVERNOR;
        timelockController = new TimelockController(
            TIMELOCK_DELAY,
            proposerCancellerAddresses,
            executorAddresses
        );

        grlm = new GlobalRateLimitedMinter(
            address(core),
            MAX_RATE_LIMIT_PER_SECOND_MINTING,
            RATE_LIMIT_PER_SECOND_MINTING,
            BUFFER_CAP_MINTING
        );
        gserl = new GlobalSystemExitRateLimiter(
            address(core),
            MAX_RATE_LIMIT_PER_SECOND_EXITING,
            RATE_LIMIT_PER_SECOND_EXIT,
            BUFFER_CAP_EXITING
        );

        /// VOLT rate
        vso = new VoltSystemOracle(
            address(core),
            VOLT_MONTHLY_BASIS_POINTS,
            VOLT_APR_START_TIME,
            VOLT_START_PRICE
        );

        /// PCV Deposits
        morphoDaiPCVDeposit = new MorphoCompoundPCVDeposit(
            address(core),
            MainnetAddresses.CDAI,
            address(dai),
            MainnetAddresses.MORPHO,
            MainnetAddresses.MORPHO_LENS
        );
        morphoUsdcPCVDeposit = new MorphoCompoundPCVDeposit(
            address(core),
            MainnetAddresses.CUSDC,
            address(usdc),
            MainnetAddresses.MORPHO,
            MainnetAddresses.MORPHO_LENS
        );

        /// Peg Stability
        daipsm = new PegStabilityModule(
            address(core),
            address(vso),
            address(0),
            0,
            false,
            dai,
            VOLT_FLOOR_PRICE_DAI,
            VOLT_CEILING_PRICE_DAI
        );
        usdcpsm = new PegStabilityModule(
            address(core),
            address(vso),
            address(0),
            -12,
            false,
            usdc,
            VOLT_FLOOR_PRICE_USDC,
            VOLT_CEILING_PRICE_USDC
        );
        usdcNonCustodialPsm = new NonCustodialPSM(
            address(core),
            address(vso),
            address(0),
            -12,
            false,
            usdc,
            VOLT_FLOOR_PRICE_USDC,
            VOLT_CEILING_PRICE_USDC,
            IPCVDeposit(address(morphoUsdcPCVDeposit))
        );
        daiNonCustodialPsm = new NonCustodialPSM(
            address(core),
            address(vso),
            address(0),
            0,
            false,
            dai,
            VOLT_FLOOR_PRICE_DAI,
            VOLT_CEILING_PRICE_DAI,
            IPCVDeposit(address(morphoDaiPCVDeposit))
        );
        allocator = new ERC20Allocator(address(core));

        /// PCV Movement
        systemEntry = new SystemEntry(address(core));

        pcvSwapperMaker = new MakerPCVSwapper(address(core));

        address[] memory pcvGuardianSafeAddresses = new address[](4);
        pcvGuardianSafeAddresses[0] = address(morphoDaiPCVDeposit);
        pcvGuardianSafeAddresses[1] = address(morphoUsdcPCVDeposit);
        pcvGuardianSafeAddresses[2] = address(usdcpsm);
        pcvGuardianSafeAddresses[3] = address(daipsm);
        pcvGuardian = new PCVGuardian(
            address(core),
            address(timelockController),
            pcvGuardianSafeAddresses
        );

        pcvRouter = new PCVRouter(address(core));

        /// Accounting
        pcvOracle = new PCVOracle(address(core));
        daiConstantOracle = new ConstantPriceOracle(address(core), 1e18);
        usdcConstantOracle = new ConstantPriceOracle(
            address(core),
            1e18 * 10 ** uint256(uint8(USDC_DECIMALS_NORMALIZER))
        );
    }

    function setUp(address deployer) public {
        /// Set references in Core
        core.setVolt(IVolt(address(volt)));
        core.setGlobalRateLimitedMinter(
            IGlobalRateLimitedMinter(address(grlm))
        );
        core.setGlobalSystemExitRateLimiter(
            IGlobalSystemExitRateLimiter(address(gserl))
        );
        core.setPCVOracle(IPCVOracle(address(pcvOracle)));

        /// Grant Roles
        core.grantGovernor(address(timelockController));
        core.grantGovernor(MainnetAddresses.GOVERNOR); /// team multisig

        core.grantPCVController(address(allocator));
        core.grantPCVController(address(pcvGuardian));
        core.grantPCVController(address(pcvRouter));
        core.grantPCVController(MainnetAddresses.GOVERNOR); /// team multisig
        core.grantPCVController(address(daiNonCustodialPsm));
        core.grantPCVController(address(usdcNonCustodialPsm));

        core.createRole(VoltRoles.PCV_MOVER, VoltRoles.GOVERNOR);
        core.grantRole(VoltRoles.PCV_MOVER, MainnetAddresses.GOVERNOR); /// team multisig

        core.createRole(VoltRoles.LIQUID_PCV_DEPOSIT, VoltRoles.GOVERNOR);
        core.createRole(VoltRoles.ILLIQUID_PCV_DEPOSIT, VoltRoles.GOVERNOR);
        core.grantRole(VoltRoles.LIQUID_PCV_DEPOSIT, address(daipsm));
        core.grantRole(VoltRoles.LIQUID_PCV_DEPOSIT, address(usdcpsm));
        core.grantRole(
            VoltRoles.LIQUID_PCV_DEPOSIT,
            address(morphoDaiPCVDeposit)
        );
        core.grantRole(
            VoltRoles.LIQUID_PCV_DEPOSIT,
            address(morphoUsdcPCVDeposit)
        );

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

        core.grantSystemExitRateLimitDepleter(address(daiNonCustodialPsm));
        core.grantSystemExitRateLimitDepleter(address(usdcNonCustodialPsm));

        core.grantSystemExitRateLimitReplenisher(address(allocator));

        core.grantLocker(address(systemEntry));
        core.grantLocker(address(allocator));
        core.grantLocker(address(pcvOracle));
        core.grantLocker(address(daipsm));
        core.grantLocker(address(usdcpsm));
        core.grantLocker(address(morphoDaiPCVDeposit));
        core.grantLocker(address(morphoUsdcPCVDeposit));
        core.grantLocker(address(grlm));
        core.grantLocker(address(gserl));
        core.grantLocker(address(pcvRouter));
        core.grantLocker(address(pcvGuardian));
        core.grantLocker(address(daiNonCustodialPsm));
        core.grantLocker(address(usdcNonCustodialPsm));

        core.grantMinter(address(grlm));

        /// Allocator config
        allocator.connectPSM(
            address(usdcpsm),
            USDC_TARGET_BALANCE,
            USDC_DECIMALS_NORMALIZER
        );
        allocator.connectPSM(
            address(daipsm),
            DAI_TARGET_BALANCE,
            DAI_DECIMALS_NORMALIZER
        );
        allocator.connectDeposit(
            address(usdcpsm),
            address(morphoUsdcPCVDeposit)
        );
        allocator.connectDeposit(address(daipsm), address(morphoDaiPCVDeposit));

        /// Configure PCV Oracle
        address[] memory venues = new address[](4);
        venues[0] = address(morphoDaiPCVDeposit);
        venues[1] = address(morphoUsdcPCVDeposit);
        venues[2] = address(daipsm);
        venues[3] = address(usdcpsm);

        address[] memory oracles = new address[](4);
        oracles[0] = address(daiConstantOracle);
        oracles[1] = address(usdcConstantOracle);
        oracles[2] = address(daiConstantOracle);
        oracles[3] = address(usdcConstantOracle);

        bool[] memory isLiquid = new bool[](4);
        isLiquid[0] = true;
        isLiquid[1] = true;
        isLiquid[2] = true;
        isLiquid[3] = true;

        pcvOracle.addVenues(venues, oracles, isLiquid);

        /// Configure PCV Router
        address[] memory swappers = new address[](1);
        swappers[0] = address(pcvSwapperMaker);
        pcvRouter.addPCVSwappers(swappers);

        /// Allow all addresses to execute proposals once completed
        timelockController.grantRole(
            timelockController.EXECUTOR_ROLE(),
            address(0)
        );
        /// Cleanup
        timelockController.renounceRole(
            timelockController.TIMELOCK_ADMIN_ROLE(),
            deployer
        );
        core.revokeGovernor(deployer);
    }
}
