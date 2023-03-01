//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {Proposal} from "@test/proposals/proposalTypes/Proposal.sol";
import {Addresses} from "@test/proposals/Addresses.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {IVolt} from "@voltprotocol/volt/IVolt.sol";
import {CoreV2} from "@voltprotocol/core/CoreV2.sol";
import {VoltV2} from "@voltprotocol/volt/VoltV2.sol";
import {VoltRoles} from "@voltprotocol/core/VoltRoles.sol";
import {PCVRouter} from "@voltprotocol/pcv/PCVRouter.sol";
import {PCVOracle} from "@voltprotocol/oracle/PCVOracle.sol";
import {CoreRefV2} from "@voltprotocol/refs/CoreRefV2.sol";
import {IPCVOracle} from "@voltprotocol/oracle/IPCVOracle.sol";
import {PCVDeposit} from "@voltprotocol/pcv/PCVDeposit.sol";
import {SystemEntry} from "@voltprotocol/entry/SystemEntry.sol";
import {PCVGuardian} from "@voltprotocol/pcv/PCVGuardian.sol";
import {IOracleRefV2} from "@voltprotocol/refs/IOracleRefV2.sol";
import {IPCVDepositV2} from "@voltprotocol/pcv/IPCVDepositV2.sol";
import {NonCustodialPSM} from "@voltprotocol/peg/NonCustodialPSM.sol";
import {MakerPCVSwapper} from "@voltprotocol/pcv/maker/MakerPCVSwapper.sol";
import {VoltSystemOracle} from "@voltprotocol/oracle/VoltSystemOracle.sol";
import {EulerPCVDeposit} from "@voltprotocol/pcv/euler/EulerPCVDeposit.sol";
import {IPegStabilityModule} from "@voltprotocol/peg/IPegStabilityModule.sol";
import {ConstantPriceOracle} from "@voltprotocol/oracle/ConstantPriceOracle.sol";
import {CompoundBadDebtSentinel} from "@voltprotocol/pcv/compound/CompoundBadDebtSentinel.sol";
import {IGlobalReentrancyLock, GlobalReentrancyLock} from "@voltprotocol/core/GlobalReentrancyLock.sol";
import {IGlobalRateLimitedMinter, GlobalRateLimitedMinter} from "@voltprotocol/rate-limits/GlobalRateLimitedMinter.sol";

/*
VIP16 Executes after VIP15 (SystemV1 deprecation), and deploys the new SystemV2.
VIP16 does not do any multisig or timelock actions, only deployment of contracts
and tying them together properly.
*/

contract vip16 is Proposal {
    using SafeCast for *;

    string public name = "VIP16";

    /// Parameters
    uint256 public constant TIMELOCK_DELAY = 86400;

    /// ---------- ORACLE PARAM ----------

    /// @notice price changes by 14 basis points per month,
    /// making non compounded annual rate 1.68%
    uint112 monthlyChangeRate = 0.0014e18;

    /// ---------- COMPOUND BAD DEBT SENTINEL PARAM ----------

    /// @notice bad debt threshold is $1m
    uint256 badDebtThreshold = 1_000_000e18;

    /// ---------- RATE LIMITED MINTER PARAMS ----------

    /// maximum rate limit per second is 100 VOLT
    uint256 public constant MAX_RATE_LIMIT_PER_SECOND_MINTING = 100e18;

    /// replenish 0 VOLT per day
    uint64 public constant RATE_LIMIT_PER_SECOND_MINTING = 0;

    /// buffer cap of 3m VOLT
    uint96 public constant BUFFER_CAP_MINTING = 3_000_000e18;

    /// ---------- RATE LIMITED MINTER PARAMS ----------

    /// maximum rate limit per second is $100
    uint256 public constant MAX_RATE_LIMIT_PER_SECOND_EXITING = 100e18;

    /// replenish 500k VOLT per day ($5.787 dollars per second)
    uint128 public constant RATE_LIMIT_PER_SECOND_EXIT = 5787037037037037000;

    /// buffer cap of 0.5m VOLT
    uint128 public constant BUFFER_CAP_EXITING = 500_000e18;

    /// ---------- PSM PARAMS ----------

    uint128 public constant VOLT_FLOOR_PRICE_USDC = 1.05e6;
    uint128 public constant VOLT_CEILING_PRICE_USDC = 1.10e6;
    uint128 public constant VOLT_FLOOR_PRICE_DAI = 1.05e18;
    uint128 public constant VOLT_CEILING_PRICE_DAI = 1.10e18;
    uint248 public constant USDC_TARGET_BALANCE = 10_000e6;
    uint248 public constant DAI_TARGET_BALANCE = 10_000e18;
    int8 public constant USDC_DECIMALS_NORMALIZER = 12;
    int8 public constant DAI_DECIMALS_NORMALIZER = 0;

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
                RATE_LIMIT_PER_SECOND_MINTING,
                BUFFER_CAP_MINTING
            );

            addresses.addMainnet(
                "TIMELOCK_CONTROLLER",
                address(timelockController)
            );
            addresses.addMainnet("GLOBAL_RATE_LIMITED_MINTER", address(grlm));
        }
        {
            /// Euler Deposits
            EulerPCVDeposit eulerDaiPCVDeposit = new EulerPCVDeposit(
                addresses.mainnet("CORE"),
                addresses.mainnet("EULER_DAI"),
                addresses.mainnet("EULER_MAIN"),
                addresses.mainnet("DAI"),
                address(0)
            );

            EulerPCVDeposit eulerUsdcPCVDeposit = new EulerPCVDeposit(
                addresses.mainnet("CORE"),
                addresses.mainnet("EULER_USDC"),
                addresses.mainnet("EULER_MAIN"),
                addresses.mainnet("USDC"),
                address(0)
            );

            addresses.addMainnet(
                "PCV_DEPOSIT_EULER_DAI",
                address(eulerDaiPCVDeposit)
            );
            addresses.addMainnet(
                "PCV_DEPOSIT_EULER_USDC",
                address(eulerUsdcPCVDeposit)
            );
        }

        /// VOLT rate
        {
            VoltSystemOracle vso = new VoltSystemOracle(
                addresses.mainnet("CORE")
            );

            addresses.addMainnet("VOLT_SYSTEM_ORACLE", address(vso));
        }

        /// Peg Stability
        {
            // NonCustodialPSM usdcNonCustodialPsm = new NonCustodialPSM(
            //     addresses.mainnet("CORE"),
            //     addresses.mainnet("VOLT_SYSTEM_ORACLE"),
            //     address(0),
            //     -12,
            //     false,
            //     IERC20(addresses.mainnet("USDC")),
            //     VOLT_FLOOR_PRICE_USDC,
            //     VOLT_CEILING_PRICE_USDC,
            //     IPCVDepositV2(
            //         addresses.mainnet("PCV_DEPOSIT_MORPHO_COMPOUND_USDC")
            //     )
            // );
            // NonCustodialPSM daiNonCustodialPsm = new NonCustodialPSM(
            //     addresses.mainnet("CORE"),
            //     addresses.mainnet("VOLT_SYSTEM_ORACLE"),
            //     address(0),
            //     0,
            //     false,
            //     IERC20(addresses.mainnet("DAI")),
            //     VOLT_FLOOR_PRICE_DAI,
            //     VOLT_CEILING_PRICE_DAI,
            //     IPCVDepositV2(
            //         addresses.mainnet("PCV_DEPOSIT_MORPHO_COMPOUND_DAI")
            //     )
            // );
            // addresses.addMainnet(
            //     "PSM_NONCUSTODIAL_USDC",
            //     address(usdcNonCustodialPsm)
            // );
            // addresses.addMainnet(
            //     "PSM_NONCUSTODIAL_DAI",
            //     address(daiNonCustodialPsm)
            // );
        }

        /// PCV Movement
        {
            SystemEntry systemEntry = new SystemEntry(
                addresses.mainnet("CORE")
            );

            MakerPCVSwapper pcvSwapperMaker = new MakerPCVSwapper(
                addresses.mainnet("CORE")
            );

            address[] memory pcvGuardianSafeAddresses = new address[](0);
            // pcvGuardianSafeAddresses[0] = addresses.mainnet(
            //     "PCV_DEPOSIT_MORPHO_COMPOUND_DAI"
            // );
            // pcvGuardianSafeAddresses[1] = addresses.mainnet(
            //     "PCV_DEPOSIT_MORPHO_COMPOUND_USDC"
            // );
            // pcvGuardianSafeAddresses[2] = addresses.mainnet(
            //     "PCV_DEPOSIT_EULER_DAI"
            // );
            // pcvGuardianSafeAddresses[3] = addresses.mainnet(
            //     "PCV_DEPOSIT_EULER_USDC"
            // );
            // pcvGuardianSafeAddresses[4] = addresses.mainnet(
            //     "PCV_DEPOSIT_MORPHO_AAVE_DAI"
            // );
            // pcvGuardianSafeAddresses[5] = addresses.mainnet(
            //     "PCV_DEPOSIT_MORPHO_AAVE_USDC"
            // );

            PCVGuardian pcvGuardian = new PCVGuardian(
                addresses.mainnet("CORE"),
                addresses.mainnet("TIMELOCK_CONTROLLER"),
                pcvGuardianSafeAddresses
            );

            PCVRouter pcvRouter = new PCVRouter(addresses.mainnet("CORE"));

            CompoundBadDebtSentinel badDebtSentinel = new CompoundBadDebtSentinel(
                    addresses.mainnet("CORE"),
                    addresses.mainnet("COMPTROLLER_V2"),
                    address(pcvGuardian),
                    badDebtThreshold
                );

            addresses.addMainnet("SYSTEM_ENTRY", address(systemEntry));
            addresses.addMainnet("PCV_SWAPPER_MAKER", address(pcvSwapperMaker));
            addresses.addMainnet("PCV_GUARDIAN", address(pcvGuardian));
            addresses.addMainnet("PCV_ROUTER", address(pcvRouter));
            addresses.addMainnet(
                "COMPOUND_BAD_DEBT_SENTINEL",
                address(badDebtSentinel)
            );
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
        PCVOracle pcvOracle = PCVOracle(addresses.mainnet("PCV_ORACLE"));
        PCVRouter pcvRouter = PCVRouter(addresses.mainnet("PCV_ROUTER"));
        VoltSystemOracle oracle = VoltSystemOracle(
            addresses.mainnet("VOLT_SYSTEM_ORACLE")
        );

        /// Set references in Core
        core.setVolt(IVolt(addresses.mainnet("VOLT")));
        core.setGlobalRateLimitedMinter(
            IGlobalRateLimitedMinter(
                addresses.mainnet("GLOBAL_RATE_LIMITED_MINTER")
            )
        );
        core.setPCVOracle(IPCVOracle(addresses.mainnet("PCV_ORACLE")));
        core.setGlobalReentrancyLock(
            IGlobalReentrancyLock(addresses.mainnet("GLOBAL_LOCK"))
        );

        /// Grant Roles
        core.grantGovernor(addresses.mainnet("TIMELOCK_CONTROLLER"));
        core.grantGovernor(addresses.mainnet("GOVERNOR")); /// team multisig

        core.grantPCVController(addresses.mainnet("PCV_GUARDIAN"));
        core.grantPCVController(addresses.mainnet("PCV_ROUTER"));
        core.grantPCVController(addresses.mainnet("GOVERNOR")); /// team multisig
        // core.grantPCVController(addresses.mainnet("PSM_NONCUSTODIAL_DAI"));
        // core.grantPCVController(addresses.mainnet("PSM_NONCUSTODIAL_USDC"));

        core.createRole(VoltRoles.PCV_MOVER, VoltRoles.GOVERNOR);
        core.grantRole(VoltRoles.PCV_MOVER, addresses.mainnet("GOVERNOR")); /// team multisig

        // core.createRole(VoltRoles.PSM_MINTER, VoltRoles.GOVERNOR);
        // core.grantRole(
        //     VoltRoles.PSM_MINTER,
        //     addresses.mainnet("PSM_NONCUSTODIAL_DAI")
        // );
        // core.grantRole(
        //     VoltRoles.PSM_MINTER,
        //     addresses.mainnet("PSM_NONCUSTODIAL_USDC")
        // );

        core.createRole(VoltRoles.PCV_DEPOSIT, VoltRoles.GOVERNOR);
        // core.grantRole(
        //     VoltRoles.PCV_DEPOSIT,
        //     addresses.mainnet("PCV_DEPOSIT_MORPHO_COMPOUND_DAI")
        // );
        // core.grantRole(
        //     VoltRoles.PCV_DEPOSIT,
        //     addresses.mainnet("PCV_DEPOSIT_MORPHO_COMPOUND_USDC")
        // );
        // core.grantRole(
        //     VoltRoles.PCV_DEPOSIT,
        //     addresses.mainnet("PCV_DEPOSIT_MORPHO_AAVE_DAI")
        // );
        // core.grantRole(
        //     VoltRoles.PCV_DEPOSIT,
        //     addresses.mainnet("PCV_DEPOSIT_MORPHO_AAVE_USDC")
        // );
        core.grantRole(
            VoltRoles.PCV_DEPOSIT,
            addresses.mainnet("PCV_DEPOSIT_EULER_DAI")
        );
        core.grantRole(
            VoltRoles.PCV_DEPOSIT,
            addresses.mainnet("PCV_DEPOSIT_EULER_USDC")
        );

        core.grantPCVGuard(addresses.mainnet("EOA_1"));
        core.grantPCVGuard(addresses.mainnet("EOA_2"));
        core.grantPCVGuard(addresses.mainnet("EOA_4"));

        core.grantGuardian(addresses.mainnet("PCV_GUARDIAN"));
        core.grantGuardian(addresses.mainnet("GOVERNOR")); /// team multisig
        core.grantGuardian(addresses.mainnet("COMPOUND_BAD_DEBT_SENTINEL"));

        // core.grantPsmMinter(addresses.mainnet("PSM_NONCUSTODIAL_DAI"));
        // core.grantPsmMinter(addresses.mainnet("PSM_NONCUSTODIAL_USDC"));

        core.grantLocker(addresses.mainnet("SYSTEM_ENTRY"));
        core.grantLocker(addresses.mainnet("PCV_ORACLE"));
        // core.grantLocker(addresses.mainnet("PCV_DEPOSIT_MORPHO_COMPOUND_DAI"));
        // core.grantLocker(addresses.mainnet("PCV_DEPOSIT_MORPHO_COMPOUND_USDC"));
        core.grantLocker(addresses.mainnet("GLOBAL_RATE_LIMITED_MINTER"));
        core.grantLocker(addresses.mainnet("PCV_ROUTER"));
        core.grantLocker(addresses.mainnet("PCV_GUARDIAN"));
        // core.grantLocker(addresses.mainnet("PSM_NONCUSTODIAL_DAI"));
        // core.grantLocker(addresses.mainnet("PSM_NONCUSTODIAL_USDC"));
        core.grantLocker(addresses.mainnet("PCV_DEPOSIT_EULER_DAI"));
        core.grantLocker(addresses.mainnet("PCV_DEPOSIT_EULER_USDC"));
        // core.grantLocker(addresses.mainnet("PCV_DEPOSIT_MORPHO_AAVE_DAI"));
        // core.grantLocker(addresses.mainnet("PCV_DEPOSIT_MORPHO_AAVE_USDC"));

        core.grantMinter(addresses.mainnet("GLOBAL_RATE_LIMITED_MINTER"));

        /// Configure PCV Oracle
        address[] memory venues = new address[](2);
        // venues[0] = addresses.mainnet("PCV_DEPOSIT_MORPHO_COMPOUND_DAI");
        // venues[1] = addresses.mainnet("PCV_DEPOSIT_MORPHO_COMPOUND_USDC");
        venues[0] = addresses.mainnet("PCV_DEPOSIT_EULER_DAI");
        venues[1] = addresses.mainnet("PCV_DEPOSIT_EULER_USDC");
        // venues[4] = addresses.mainnet("PCV_DEPOSIT_MORPHO_AAVE_DAI");
        // venues[5] = addresses.mainnet("PCV_DEPOSIT_MORPHO_AAVE_USDC");

        address[] memory oracles = new address[](2);
        oracles[0] = addresses.mainnet("ORACLE_CONSTANT_DAI");
        oracles[1] = addresses.mainnet("ORACLE_CONSTANT_USDC");
        // oracles[2] = addresses.mainnet("ORACLE_CONSTANT_DAI");
        // oracles[3] = addresses.mainnet("ORACLE_CONSTANT_USDC");
        // oracles[4] = addresses.mainnet("ORACLE_CONSTANT_DAI");
        // oracles[5] = addresses.mainnet("ORACLE_CONSTANT_USDC");

        pcvOracle.addVenues(venues, oracles);

        /// Configure PCV Router
        address[] memory swappers = new address[](1);
        swappers[0] = addresses.mainnet("PCV_SWAPPER_MAKER");
        pcvRouter.addPCVSwappers(swappers);

        CompoundBadDebtSentinel badDebtSentinel = CompoundBadDebtSentinel(
            addresses.mainnet("COMPOUND_BAD_DEBT_SENTINEL")
        );

        /// add morpho PCV deposits to the compound bad debt sentinel
        badDebtSentinel.addPCVDeposits(venues);

        /// Enable new oracle
        oracle.initialize(
            addresses.mainnet("VOLT_SYSTEM_ORACLE_144_BIPS"),
            monthlyChangeRate
        );

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

    function validate(Addresses addresses, address /* deployer*/) public {
        CoreV2 core = CoreV2(addresses.mainnet("CORE"));
        PCVOracle pcvOracle = PCVOracle(addresses.mainnet("PCV_ORACLE"));
        PCVRouter pcvRouter = PCVRouter(addresses.mainnet("PCV_ROUTER"));
        VoltSystemOracle oracle = VoltSystemOracle(
            addresses.mainnet("VOLT_SYSTEM_ORACLE")
        );
        VoltSystemOracle oldOracle = VoltSystemOracle(
            addresses.mainnet("VOLT_SYSTEM_ORACLE_144_BIPS")
        );
        CompoundBadDebtSentinel badDebtSentinel = CompoundBadDebtSentinel(
            addresses.mainnet("COMPOUND_BAD_DEBT_SENTINEL")
        );

        /*--------------------------------------------------------------------
        Validate that everything reference Core properly
        --------------------------------------------------------------------*/
        assertEq(
            address(CoreRefV2(addresses.mainnet("VOLT")).core()),
            address(core)
        );
        assertEq(
            address(
                CoreRefV2(addresses.mainnet("COMPOUND_BAD_DEBT_SENTINEL"))
                    .core()
            ),
            address(core)
        );
        assertEq(
            address(CoreRefV2(addresses.mainnet("GLOBAL_LOCK")).core()),
            address(core)
        );
        // TIMELOCK_CONTROLLER is not CoreRef
        assertEq(
            address(
                CoreRefV2(addresses.mainnet("GLOBAL_RATE_LIMITED_MINTER"))
                    .core()
            ),
            address(core)
        );
        assertEq(
            address(CoreRefV2(addresses.mainnet("VOLT_SYSTEM_ORACLE")).core()),
            address(core)
        );
        // assertEq(
        //     address(
        //         CoreRefV2(addresses.mainnet("PCV_DEPOSIT_MORPHO_COMPOUND_DAI"))
        //             .core()
        //     ),
        //     address(core)
        // );
        // assertEq(
        //     address(
        //         CoreRefV2(addresses.mainnet("PCV_DEPOSIT_MORPHO_COMPOUND_USDC"))
        //             .core()
        //     ),
        //     address(core)
        // );
        assertEq(
            address(
                CoreRefV2(addresses.mainnet("PCV_DEPOSIT_EULER_DAI")).core()
            ),
            address(core)
        );
        assertEq(
            address(
                CoreRefV2(addresses.mainnet("PCV_DEPOSIT_EULER_USDC")).core()
            ),
            address(core)
        );
        // assertEq(
        //     address(
        //         CoreRefV2(addresses.mainnet("PCV_DEPOSIT_MORPHO_AAVE_DAI"))
        //             .core()
        //     ),
        //     address(core)
        // );
        // assertEq(
        //     address(
        //         CoreRefV2(addresses.mainnet("PCV_DEPOSIT_MORPHO_AAVE_USDC"))
        //             .core()
        //     ),
        //     address(core)
        // );
        // assertEq(
        //     address(
        //         CoreRefV2(addresses.mainnet("PSM_NONCUSTODIAL_USDC")).core()
        //     ),
        //     address(core)
        // );
        // assertEq(
        //     address(
        //         CoreRefV2(addresses.mainnet("PSM_NONCUSTODIAL_DAI")).core()
        //     ),
        //     address(core)
        // );
        // V1_MIGRATION_ROUTER is not CoreRef, it is only a util contract to call other contracts
        assertEq(
            address(CoreRefV2(addresses.mainnet("SYSTEM_ENTRY")).core()),
            address(core)
        );
        assertEq(
            address(CoreRefV2(addresses.mainnet("PCV_SWAPPER_MAKER")).core()),
            address(core)
        );
        assertEq(
            address(CoreRefV2(addresses.mainnet("PCV_GUARDIAN")).core()),
            address(core)
        );
        assertEq(
            address(CoreRefV2(addresses.mainnet("PCV_ROUTER")).core()),
            address(core)
        );
        assertEq(
            address(CoreRefV2(addresses.mainnet("PCV_ORACLE")).core()),
            address(core)
        );
        assertEq(
            address(CoreRefV2(addresses.mainnet("ORACLE_CONSTANT_DAI")).core()),
            address(core)
        );
        assertEq(
            address(
                CoreRefV2(addresses.mainnet("ORACLE_CONSTANT_USDC")).core()
            ),
            address(core)
        );

        assertApproxEq(
            oracle.getCurrentOraclePrice().toInt256(),
            oldOracle.getCurrentOraclePrice().toInt256(),
            0
        );

        /*--------------------------------------------------------------------
        Validate that the smart contracts are correctly linked to each other.
        --------------------------------------------------------------------*/
        // core references
        assertEq(address(core.volt()), addresses.mainnet("VOLT"));
        assertEq(address(core.vcon()), address(0));
        assertEq(
            address(core.globalRateLimitedMinter()),
            addresses.mainnet("GLOBAL_RATE_LIMITED_MINTER")
        );
        assertEq(address(core.pcvOracle()), addresses.mainnet("PCV_ORACLE"));

        // pcv oracle
        assertEq(pcvOracle.getVenues().length, 2);
        // assertEq(
        //     pcvOracle.getVenues()[0],
        //     addresses.mainnet("PCV_DEPOSIT_MORPHO_COMPOUND_DAI")
        // );
        // assertEq(
        //     pcvOracle.getVenues()[1],
        //     addresses.mainnet("PCV_DEPOSIT_MORPHO_COMPOUND_USDC")
        // );
        assertEq(
            pcvOracle.getVenues()[0],
            addresses.mainnet("PCV_DEPOSIT_EULER_DAI")
        );
        assertEq(
            pcvOracle.getVenues()[1],
            addresses.mainnet("PCV_DEPOSIT_EULER_USDC")
        );
        // assertEq(
        //     pcvOracle.getVenues()[4],
        //     addresses.mainnet("PCV_DEPOSIT_MORPHO_AAVE_DAI")
        // );
        // assertEq(
        //     pcvOracle.getVenues()[5],
        //     addresses.mainnet("PCV_DEPOSIT_MORPHO_AAVE_USDC")
        // );

        // pcv router
        assertTrue(
            pcvRouter.isPCVSwapper(addresses.mainnet("PCV_SWAPPER_MAKER"))
        );

        // oracle references
        // assertEq(
        //     address(
        //         IOracleRefV2(addresses.mainnet("PSM_NONCUSTODIAL_DAI")).oracle()
        //     ),
        //     addresses.mainnet("VOLT_SYSTEM_ORACLE")
        // );
        // assertEq(
        //     address(
        //         IOracleRefV2(addresses.mainnet("PSM_NONCUSTODIAL_USDC"))
        //             .oracle()
        //     ),
        //     addresses.mainnet("VOLT_SYSTEM_ORACLE")
        // );

        /// compound bad debt sentinel
        // assertTrue(
        //     badDebtSentinel.isCompoundPcvDeposit(
        //         addresses.mainnet("PCV_DEPOSIT_MORPHO_COMPOUND_USDC")
        //     )
        // );
        // assertTrue(
        //     badDebtSentinel.isCompoundPcvDeposit(
        //         addresses.mainnet("PCV_DEPOSIT_MORPHO_COMPOUND_DAI")
        //     )
        // );
        assertEq(
            badDebtSentinel.pcvGuardian(),
            addresses.mainnet("PCV_GUARDIAN")
        );
        assertEq(
            badDebtSentinel.comptroller(),
            addresses.mainnet("COMPTROLLER_V2")
        );
        assertEq(badDebtSentinel.badDebtThreshold(), badDebtThreshold);
    }
}
