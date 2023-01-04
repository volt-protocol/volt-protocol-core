//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {Proposal} from "../proposalTypes/Proposal.sol";
import {Addresses} from "../Addresses.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {IVolt} from "../../../volt/IVolt.sol";
import {CoreV2} from "../../../core/CoreV2.sol";
import {VoltV2} from "../../../volt/VoltV2.sol";
import {VoltRoles} from "../../../core/VoltRoles.sol";
import {MockERC20} from "../../../mock/MockERC20.sol";
import {PCVRouter} from "../../../pcv/PCVRouter.sol";
import {PCVOracle} from "../../../oracle/PCVOracle.sol";
import {IPCVOracle} from "../../../oracle/IPCVOracle.sol";
import {SystemEntry} from "../../../entry/SystemEntry.sol";
import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";
import {MockCoreRefV2} from "../../../mock/MockCoreRefV2.sol";
import {ERC20Allocator} from "../../../pcv/utils/ERC20Allocator.sol";
import {NonCustodialPSM} from "../../../peg/NonCustodialPSM.sol";
import {MakerPCVSwapper} from "../../../pcv/maker/MakerPCVSwapper.sol";
import {VoltSystemOracle} from "../../../oracle/VoltSystemOracle.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";
import {ConstantPriceOracle} from "../../../oracle/ConstantPriceOracle.sol";
import {IPCVDeposit, PCVDeposit} from "../../../pcv/PCVDeposit.sol";
import {MorphoCompoundPCVDeposit} from "../../../pcv/morpho/MorphoCompoundPCVDeposit.sol";
import {IGlobalReentrancyLock, GlobalReentrancyLock} from "../../../core/GlobalReentrancyLock.sol";
import {IGlobalRateLimitedMinter, GlobalRateLimitedMinter} from "../../../limiter/GlobalRateLimitedMinter.sol";
import {IGlobalSystemExitRateLimiter, GlobalSystemExitRateLimiter} from "../../../limiter/GlobalSystemExitRateLimiter.sol";

/*
VIP16 Executes after VIP15 (SystemV1 deprecation), and deploys the new SystemV2.
VIP16 does not do any multisig or timelock actions, only deployment of contracts
and tying them together properly.
*/

contract vip16 is Proposal {
    string public name = "VIP16";

    /// Parameters
    uint256 public constant TIMELOCK_DELAY = 86400;

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

    function deploy(Addresses addresses) public {
        /// Core
        {
            CoreV2 core = new CoreV2(addresses.mainnet("VOLT"));
            VoltV2 volt = new VoltV2(address(core));

            GlobalReentrancyLock lock = new GlobalReentrancyLock(address(core));

            addresses.addMainnet("CORE", address(core));
            addresses.addMainnet("VOLT", address(volt));
            addresses.addMainnet("GLOBAL_LOCK", address(lock));
        }

        /// all addresses will be able to execute
        {
            address[] memory executorAddresses = new address[](0);

            address[] memory proposerCancellerAddresses = new address[](1);
            proposerCancellerAddresses[0] = addresses.mainnet("GOVERNOR");
            TimelockController timelockController = new TimelockController(
                TIMELOCK_DELAY,
                proposerCancellerAddresses,
                executorAddresses
            );

            GlobalRateLimitedMinter grlm = new GlobalRateLimitedMinter(
                addresses.mainnet("CORE"),
                MAX_RATE_LIMIT_PER_SECOND_MINTING,
                RATE_LIMIT_PER_SECOND_MINTING, /// todo fix this
                BUFFER_CAP_MINTING /// todo fix this
            );
            GlobalSystemExitRateLimiter gserl = new GlobalSystemExitRateLimiter(
                addresses.mainnet("CORE"),
                MAX_RATE_LIMIT_PER_SECOND_EXITING,
                RATE_LIMIT_PER_SECOND_EXIT,
                BUFFER_CAP_EXITING
            );

            addresses.addMainnet(
                "TIMELOCK_CONTROLLER",
                address(timelockController)
            );
            addresses.addMainnet("GLOBAL_RATE_LIMITED_MINTER", address(grlm));
            addresses.addMainnet(
                "GLOBAL_SYSTEM_EXIT_RATE_LIMITER",
                address(gserl)
            );
        }

        /// VOLT rate
        {
            VoltSystemOracle vso = new VoltSystemOracle(
                addresses.mainnet("CORE"),
                VOLT_MONTHLY_BASIS_POINTS, /// todo double check this
                VOLT_APR_START_TIME, /// todo fill in actual value
                VOLT_START_PRICE /// todo fetch this from the old oracle after warping forward 24 hours
            );

            addresses.addMainnet("VOLT_SYSTEM_ORACLE", address(vso));
        }

        /// PCV Deposits
        {
            MorphoCompoundPCVDeposit morphoDaiPCVDeposit = new MorphoCompoundPCVDeposit(
                    addresses.mainnet("CORE"),
                    addresses.mainnet("CDAI"),
                    addresses.mainnet("DAI"),
                    addresses.mainnet("MORPHO"),
                    addresses.mainnet("MORPHO_LENS")
                );

            MorphoCompoundPCVDeposit morphoUsdcPCVDeposit = new MorphoCompoundPCVDeposit(
                    addresses.mainnet("CORE"),
                    addresses.mainnet("CUSDC"),
                    addresses.mainnet("USDC"),
                    addresses.mainnet("MORPHO"),
                    addresses.mainnet("MORPHO_LENS")
                );

            addresses.addMainnet(
                "PCV_DEPOSIT_MORPHO_DAI",
                address(morphoDaiPCVDeposit)
            );
            addresses.addMainnet(
                "PCV_DEPOSIT_MORPHO_USDC",
                address(morphoUsdcPCVDeposit)
            );
        }

        /// Peg Stability
        {
            PegStabilityModule daipsm = new PegStabilityModule(
                addresses.mainnet("CORE"),
                addresses.mainnet("VOLT_SYSTEM_ORACLE"),
                address(0),
                0,
                false,
                IERC20(addresses.mainnet("DAI")),
                VOLT_FLOOR_PRICE_DAI,
                VOLT_CEILING_PRICE_DAI
            );
            PegStabilityModule usdcpsm = new PegStabilityModule(
                addresses.mainnet("CORE"),
                addresses.mainnet("VOLT_SYSTEM_ORACLE"),
                address(0),
                -12,
                false,
                IERC20(addresses.mainnet("USDC")),
                VOLT_FLOOR_PRICE_USDC,
                VOLT_CEILING_PRICE_USDC
            );
            NonCustodialPSM usdcNonCustodialPsm = new NonCustodialPSM(
                addresses.mainnet("CORE"),
                addresses.mainnet("VOLT_SYSTEM_ORACLE"),
                address(0),
                -12,
                false,
                IERC20(addresses.mainnet("USDC")),
                VOLT_FLOOR_PRICE_USDC,
                VOLT_CEILING_PRICE_USDC,
                IPCVDeposit(addresses.mainnet("PCV_DEPOSIT_MORPHO_USDC"))
            );
            NonCustodialPSM daiNonCustodialPsm = new NonCustodialPSM(
                addresses.mainnet("CORE"),
                addresses.mainnet("VOLT_SYSTEM_ORACLE"),
                address(0),
                0,
                false,
                IERC20(addresses.mainnet("DAI")),
                VOLT_FLOOR_PRICE_DAI,
                VOLT_CEILING_PRICE_DAI,
                IPCVDeposit(addresses.mainnet("PCV_DEPOSIT_MORPHO_DAI"))
            );
            ERC20Allocator allocator = new ERC20Allocator(
                addresses.mainnet("CORE")
            );

            addresses.addMainnet("PSM_DAI", address(daipsm));
            addresses.addMainnet("PSM_USDC", address(usdcpsm));
            addresses.addMainnet(
                "PSM_NONCUSTODIAL_USDC",
                address(usdcNonCustodialPsm)
            );
            addresses.addMainnet(
                "PSM_NONCUSTODIAL_DAI",
                address(daiNonCustodialPsm)
            );
            addresses.addMainnet("PSM_ALLOCATOR", address(allocator));
        }

        /// PCV Movement
        {
            SystemEntry systemEntry = new SystemEntry(
                addresses.mainnet("CORE")
            );

            MakerPCVSwapper pcvSwapperMaker = new MakerPCVSwapper(
                addresses.mainnet("CORE")
            );

            address[] memory pcvGuardianSafeAddresses = new address[](4);
            pcvGuardianSafeAddresses[0] = addresses.mainnet(
                "PCV_DEPOSIT_MORPHO_DAI"
            );
            pcvGuardianSafeAddresses[1] = addresses.mainnet(
                "PCV_DEPOSIT_MORPHO_USDC"
            );
            pcvGuardianSafeAddresses[2] = addresses.mainnet("PSM_USDC");
            pcvGuardianSafeAddresses[3] = addresses.mainnet("PSM_DAI");

            PCVGuardian pcvGuardian = new PCVGuardian(
                addresses.mainnet("CORE"),
                addresses.mainnet("TIMELOCK_CONTROLLER"),
                pcvGuardianSafeAddresses
            );

            PCVRouter pcvRouter = new PCVRouter(addresses.mainnet("CORE"));

            addresses.addMainnet("SYSTEM_ENTRY", address(systemEntry));
            addresses.addMainnet("PCV_SWAPPER_MAKER", address(pcvSwapperMaker));
            addresses.addMainnet("PCV_GUARDIAN", address(pcvGuardian));
            addresses.addMainnet("PCV_ROUTER", address(pcvRouter));
        }

        /// Accounting
        {
            PCVOracle pcvOracle = new PCVOracle(addresses.mainnet("CORE"));
            ConstantPriceOracle daiConstantOracle = new ConstantPriceOracle(
                addresses.mainnet("CORE"),
                1e18
            );
            ConstantPriceOracle usdcConstantOracle = new ConstantPriceOracle(
                addresses.mainnet("CORE"),
                1e18 * 10 ** uint256(uint8(USDC_DECIMALS_NORMALIZER))
            );

            addresses.addMainnet("PCV_ORACLE", address(pcvOracle));
            addresses.addMainnet(
                "ORACLE_CONSTANT_DAI",
                address(daiConstantOracle)
            );
            addresses.addMainnet(
                "ORACLE_CONSTANT_USDC",
                address(usdcConstantOracle)
            );
        }
    }

    function afterDeploy(Addresses addresses, address deployer) public {
        CoreV2 core = CoreV2(addresses.mainnet("CORE"));
        TimelockController timelockController = TimelockController(
            payable(addresses.mainnet("TIMELOCK_CONTROLLER"))
        );
        ERC20Allocator allocator = ERC20Allocator(
            addresses.mainnet("PSM_ALLOCATOR")
        );
        PCVOracle pcvOracle = PCVOracle(addresses.mainnet("PCV_ORACLE"));
        PCVRouter pcvRouter = PCVRouter(addresses.mainnet("PCV_ROUTER"));

        /// Set references in Core
        core.setVolt(IVolt(addresses.mainnet("VOLT")));
        core.setGlobalRateLimitedMinter(
            IGlobalRateLimitedMinter(
                addresses.mainnet("GLOBAL_RATE_LIMITED_MINTER")
            )
        );
        core.setGlobalSystemExitRateLimiter(
            IGlobalSystemExitRateLimiter(
                addresses.mainnet("GLOBAL_SYSTEM_EXIT_RATE_LIMITER")
            )
        );
        core.setPCVOracle(IPCVOracle(addresses.mainnet("PCV_ORACLE")));
        core.setGlobalReentrancyLock(
            IGlobalReentrancyLock(addresses.mainnet("GLOBAL_LOCK"))
        );

        /// Grant Roles
        core.grantGovernor(addresses.mainnet("TIMELOCK_CONTROLLER"));
        core.grantGovernor(addresses.mainnet("GOVERNOR")); /// team multisig

        core.grantPCVController(addresses.mainnet("PSM_ALLOCATOR"));
        core.grantPCVController(addresses.mainnet("PCV_GUARDIAN"));
        core.grantPCVController(addresses.mainnet("PCV_ROUTER"));
        core.grantPCVController(addresses.mainnet("GOVERNOR")); /// team multisig
        core.grantPCVController(addresses.mainnet("PSM_NONCUSTODIAL_DAI"));
        core.grantPCVController(addresses.mainnet("PSM_NONCUSTODIAL_USDC"));

        core.createRole(VoltRoles.PCV_MOVER, VoltRoles.GOVERNOR);
        core.grantRole(VoltRoles.PCV_MOVER, addresses.mainnet("GOVERNOR")); /// team multisig

        core.createRole(VoltRoles.LIQUID_PCV_DEPOSIT, VoltRoles.GOVERNOR);
        core.createRole(VoltRoles.ILLIQUID_PCV_DEPOSIT, VoltRoles.GOVERNOR);
        core.grantRole(
            VoltRoles.LIQUID_PCV_DEPOSIT,
            addresses.mainnet("PSM_DAI")
        );
        core.grantRole(
            VoltRoles.LIQUID_PCV_DEPOSIT,
            addresses.mainnet("PSM_USDC")
        );
        core.grantRole(
            VoltRoles.LIQUID_PCV_DEPOSIT,
            addresses.mainnet("PCV_DEPOSIT_MORPHO_DAI")
        );
        core.grantRole(
            VoltRoles.LIQUID_PCV_DEPOSIT,
            addresses.mainnet("PCV_DEPOSIT_MORPHO_USDC")
        );

        core.grantPCVGuard(addresses.mainnet("EOA_1"));
        core.grantPCVGuard(addresses.mainnet("EOA_2"));
        core.grantPCVGuard(addresses.mainnet("EOA_4"));

        core.grantGuardian(addresses.mainnet("PCV_GUARDIAN"));
        core.grantGuardian(addresses.mainnet("GOVERNOR")); /// team multisig

        core.grantRateLimitedMinter(addresses.mainnet("PSM_DAI"));
        core.grantRateLimitedMinter(addresses.mainnet("PSM_USDC"));

        core.grantRateLimitedRedeemer(addresses.mainnet("PSM_DAI"));
        core.grantRateLimitedRedeemer(addresses.mainnet("PSM_USDC"));
        core.grantRateLimitedRedeemer(
            addresses.mainnet("PSM_NONCUSTODIAL_DAI")
        );
        core.grantRateLimitedRedeemer(
            addresses.mainnet("PSM_NONCUSTODIAL_USDC")
        );

        core.grantSystemExitRateLimitDepleter(
            addresses.mainnet("PSM_NONCUSTODIAL_DAI")
        );
        core.grantSystemExitRateLimitDepleter(
            addresses.mainnet("PSM_NONCUSTODIAL_USDC")
        );

        core.grantSystemExitRateLimitReplenisher(
            addresses.mainnet("PSM_ALLOCATOR")
        );

        core.grantLocker(addresses.mainnet("SYSTEM_ENTRY"));
        core.grantLocker(addresses.mainnet("PSM_ALLOCATOR"));
        core.grantLocker(addresses.mainnet("PCV_ORACLE"));
        core.grantLocker(addresses.mainnet("PSM_DAI"));
        core.grantLocker(addresses.mainnet("PSM_USDC"));
        core.grantLocker(addresses.mainnet("PCV_DEPOSIT_MORPHO_DAI"));
        core.grantLocker(addresses.mainnet("PCV_DEPOSIT_MORPHO_USDC"));
        core.grantLocker(addresses.mainnet("GLOBAL_RATE_LIMITED_MINTER"));
        core.grantLocker(addresses.mainnet("GLOBAL_SYSTEM_EXIT_RATE_LIMITER"));
        core.grantLocker(addresses.mainnet("PCV_ROUTER"));
        core.grantLocker(addresses.mainnet("PCV_GUARDIAN"));
        core.grantLocker(addresses.mainnet("PSM_NONCUSTODIAL_DAI"));
        core.grantLocker(addresses.mainnet("PSM_NONCUSTODIAL_USDC"));

        core.grantMinter(addresses.mainnet("GLOBAL_RATE_LIMITED_MINTER"));

        /// Allocator config
        allocator.connectPSM(
            addresses.mainnet("PSM_USDC"),
            USDC_TARGET_BALANCE,
            USDC_DECIMALS_NORMALIZER
        );
        allocator.connectPSM(
            addresses.mainnet("PSM_DAI"),
            DAI_TARGET_BALANCE,
            DAI_DECIMALS_NORMALIZER
        );
        allocator.connectDeposit(
            addresses.mainnet("PSM_USDC"),
            addresses.mainnet("PCV_DEPOSIT_MORPHO_USDC")
        );
        allocator.connectDeposit(
            addresses.mainnet("PSM_DAI"),
            addresses.mainnet("PCV_DEPOSIT_MORPHO_DAI")
        );

        /// Configure PCV Oracle
        address[] memory venues = new address[](4);
        venues[0] = addresses.mainnet("PCV_DEPOSIT_MORPHO_DAI");
        venues[1] = addresses.mainnet("PCV_DEPOSIT_MORPHO_USDC");
        venues[2] = addresses.mainnet("PSM_DAI");
        venues[3] = addresses.mainnet("PSM_USDC");

        address[] memory oracles = new address[](4);
        oracles[0] = addresses.mainnet("ORACLE_CONSTANT_DAI");
        oracles[1] = addresses.mainnet("ORACLE_CONSTANT_USDC");
        oracles[2] = addresses.mainnet("ORACLE_CONSTANT_DAI");
        oracles[3] = addresses.mainnet("ORACLE_CONSTANT_USDC");

        bool[] memory isLiquid = new bool[](4);
        isLiquid[0] = true;
        isLiquid[1] = true;
        isLiquid[2] = true;
        isLiquid[3] = true;

        pcvOracle.addVenues(venues, oracles, isLiquid);

        /// Configure PCV Router
        address[] memory swappers = new address[](1);
        swappers[0] = addresses.mainnet("PCV_SWAPPER_MAKER");
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

    function run(Addresses addresses, address deployer) public pure {}

    function teardown(Addresses addresses, address deployer) public pure {}

    function validate(Addresses addresses, address deployer) public pure {}
}
