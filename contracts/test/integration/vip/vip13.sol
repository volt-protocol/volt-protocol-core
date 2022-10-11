//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Vm} from "./../../unit/utils/Vm.sol";
import {IVIP} from "./IVIP.sol";
import {DSTest} from "./../../unit/utils/DSTest.sol";
import {Core} from "../../../core/Core.sol";
import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";
import {ITimelockSimulation} from "../utils/ITimelockSimulation.sol";
import {ERC20Allocator} from "../../../pcv/utils/ERC20Allocator.sol";
import {ERC20CompoundPCVDeposit} from "../../../pcv/compound/ERC20CompoundPCVDeposit.sol";
import {PriceBoundPSM} from "../../../peg/PriceBoundPSM.sol";
import {IPegStabilityModule} from "../../../peg/IPegStabilityModule.sol";
import {VoltMigrator} from "../../../volt/VoltMigrator.sol";
import {VoltV2} from "../../../volt/VoltV2.sol";
import {IVolt} from "../../../volt/IVolt.sol";
import {IVoltMigrator} from "../../../volt/IVoltMigrator.sol";
import {IPCVDeposit} from "../../../pcv/IPCVDeposit.sol";
import {MigratorRouter} from "../../../pcv/MigratorRouter.sol";

contract vip13 is DSTest, IVIP {
    using SafeERC20 for IERC20;
    Vm public constant vm = Vm(HEVM_ADDRESS);
    uint256 public voltInUsdcPSM;
    uint256 public voltInDaiPSM;

    uint256 public usdcInUsdcPSM;
    uint256 public daiInDaiPSM;

    PriceBoundPSM public voltV2DaiPriceBoundPSM;
    PriceBoundPSM public voltV2UsdcPriceBoundPSM;

    VoltV2 public voltV2;
    IVolt public oldVolt = IVolt(MainnetAddresses.VOLT);

    VoltMigrator public voltMigrator;
    MigratorRouter public migratorRouter;

    ITimelockSimulation.action[] private proposal;

    uint256 oldVoltTotalSupply;
    uint256 voltDaiFloorPrice = 9_000;
    uint256 voltDaiCeilingPrice = 10_000;

    uint256 voltUsdcFloorPrice = 9_000e12;
    uint256 voltUsdcCeilingPrice = 10_000e12;

    /// @notice target token balance for the DAI PSM to hold
    uint248 private constant targetBalanceDai = 100_000e18;

    /// @notice target token balance for the USDC PSM to hold
    uint248 private constant targetBalanceUsdc = 100_000e6;

    /// @notice scale up USDC value by 12 decimals in order to account for decimal delta
    /// and properly update the buffer in ERC20Allocator
    int8 private constant usdcDecimalNormalizer = 12;

    /// @notice no scaling to do on DAI as decimals are 18
    int8 private constant daiDecimalNormalizer = 0;

    ERC20Allocator private allocator =
        ERC20Allocator(MainnetAddresses.ERC20ALLOCATOR);

    ERC20CompoundPCVDeposit private daiDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_DAI_PCV_DEPOSIT);
    ERC20CompoundPCVDeposit private usdcDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT);

    constructor() {
        if (block.chainid != 1) {
            return;
        }

        mainnetSetup();

        voltV2 = new VoltV2(MainnetAddresses.CORE);

        voltMigrator = new VoltMigrator(
            MainnetAddresses.CORE,
            IVolt(address(voltV2))
        );

        deployPsms(address(voltV2));

        migratorRouter = new MigratorRouter(
            IVolt(address(voltV2)),
            IVoltMigrator(address(voltMigrator)),
            voltV2DaiPriceBoundPSM,
            voltV2UsdcPriceBoundPSM
        );

        address[] memory toWhitelist = new address[](2);
        toWhitelist[0] = address(voltV2UsdcPriceBoundPSM);
        toWhitelist[1] = address(voltV2DaiPriceBoundPSM);

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.CORE,
                arguments: abi.encodeWithSignature(
                    "grantMinter(address)",
                    MainnetAddresses.TIMELOCK_CONTROLLER
                ),
                description: "Grant minter role to timelock"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: address(voltV2),
                arguments: abi.encodeWithSignature(
                    "mint(address,uint256)",
                    address(voltMigrator),
                    oldVoltTotalSupply
                ),
                description: "Mint new volt for new VOLT to migrator contract"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.CORE,
                arguments: abi.encodeWithSignature(
                    "revokeMinter(address)",
                    MainnetAddresses.TIMELOCK_CONTROLLER
                ),
                description: "Remove minter role from timelock"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: address(MainnetAddresses.VOLT),
                arguments: abi.encodeWithSignature(
                    "approve(address,uint256)",
                    address(voltMigrator),
                    type(uint256).max // give max approval until we have hardcoded amount
                ),
                description: "Approve migrator to use old  VOLT"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: address(voltMigrator),
                arguments: abi.encodeWithSignature(
                    "exchangeTo(address,uint256)",
                    address(voltV2UsdcPriceBoundPSM),
                    voltInUsdcPSM
                ),
                description: "Exchange new volt for new USDC PSM"
            })
        );
        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.USDC,
                arguments: abi.encodeWithSignature(
                    "transfer(address,uint256)",
                    address(voltV2UsdcPriceBoundPSM),
                    usdcInUsdcPSM
                ),
                description: "Transfer USDC to the new USDC PSM"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.DAI,
                arguments: abi.encodeWithSignature(
                    "transfer(address,uint256)",
                    address(voltV2DaiPriceBoundPSM),
                    daiInDaiPSM
                ),
                description: "Transfer DAI to the new DAI PSM"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: address(voltMigrator),
                arguments: abi.encodeWithSignature(
                    "exchangeTo(address,uint256)",
                    address(voltV2DaiPriceBoundPSM),
                    voltInDaiPSM
                ),
                description: "Exchange new volt for new DAI PSM"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.ERC20ALLOCATOR,
                arguments: abi.encodeWithSignature(
                    "disconnectPSM(address)",
                    MainnetAddresses.VOLT_USDC_PSM
                ),
                description: "Disconnect old USDC PSM from the ERC20 Allocator"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.ERC20ALLOCATOR,
                arguments: abi.encodeWithSignature(
                    "disconnectPSM(address)",
                    MainnetAddresses.VOLT_DAI_PSM
                ),
                description: "Disconnect old DAI PSM from the ERC20 Allocator"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.ERC20ALLOCATOR,
                arguments: abi.encodeWithSignature(
                    "connectPSM(address,uint248,int8)",
                    address(voltV2UsdcPriceBoundPSM),
                    targetBalanceUsdc,
                    usdcDecimalNormalizer /// 12 decimals of normalization
                ),
                description: "Add new USDC PSM to the ERC20 Allocator"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.ERC20ALLOCATOR,
                arguments: abi.encodeWithSignature(
                    "connectPSM(address,uint248,int8)",
                    address(voltV2DaiPriceBoundPSM),
                    targetBalanceDai,
                    daiDecimalNormalizer
                ),
                description: "Add new DAI PSM to the ERC20 Allocator"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.ERC20ALLOCATOR,
                arguments: abi.encodeWithSignature(
                    "connectDeposit(address,address)",
                    address(voltV2UsdcPriceBoundPSM),
                    MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT
                ),
                description: "Connect USDC deposit to PSM in ERC20 Allocator"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.ERC20ALLOCATOR,
                arguments: abi.encodeWithSignature(
                    "connectDeposit(address,address)",
                    address(voltV2DaiPriceBoundPSM),
                    MainnetAddresses.COMPOUND_DAI_PCV_DEPOSIT
                ),
                description: "Connect DAI deposit to PSM in ERC20 Allocator"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.PCV_GUARDIAN,
                arguments: abi.encodeWithSignature(
                    "addWhitelistAddresses(address[])",
                    toWhitelist
                ),
                description: "Add new DAI, and USDC PSMs to PCV Guardian whitelist"
            })
        );
    }

    function getMainnetProposal()
        public
        view
        override
        returns (ITimelockSimulation.action[] memory prop)
    {
        prop = proposal;
    }

    function mainnetSetup() public override {
        oldVoltTotalSupply = oldVolt.totalSupply();
        vm.startPrank(MainnetAddresses.GOVERNOR);

        // pull out VOLT from VOLT-USDC PSM to Governor
        uint256 governorVoltBalanceBeforeUsdc = IERC20(MainnetAddresses.VOLT)
            .balanceOf(MainnetAddresses.GOVERNOR);

        PCVGuardian(MainnetAddresses.PCV_GUARDIAN)
            .withdrawAllERC20ToSafeAddress(
                MainnetAddresses.VOLT_USDC_PSM,
                MainnetAddresses.VOLT
            );

        uint256 governorVoltBalanceAfterUsdc = IERC20(MainnetAddresses.VOLT)
            .balanceOf(MainnetAddresses.GOVERNOR);

        voltInUsdcPSM =
            governorVoltBalanceAfterUsdc -
            governorVoltBalanceBeforeUsdc;

        // pull out USDC from VOLT-USDC PSM to Governor

        uint256 governorUsdcBalanceBeforeUsdc = IERC20(MainnetAddresses.USDC)
            .balanceOf(MainnetAddresses.GOVERNOR);

        PCVGuardian(MainnetAddresses.PCV_GUARDIAN)
            .withdrawAllERC20ToSafeAddress(
                MainnetAddresses.VOLT_USDC_PSM,
                MainnetAddresses.USDC
            );

        uint256 governorUsdcBalanceAfterUsdc = IERC20(MainnetAddresses.USDC)
            .balanceOf(MainnetAddresses.GOVERNOR);

        usdcInUsdcPSM =
            governorUsdcBalanceAfterUsdc -
            governorUsdcBalanceBeforeUsdc;

        // pull out VOLT from VOLT-DAI PSM to Governor

        uint256 governorVoltBalanceBeforeDai = IERC20(MainnetAddresses.VOLT)
            .balanceOf(MainnetAddresses.GOVERNOR);

        PCVGuardian(MainnetAddresses.PCV_GUARDIAN)
            .withdrawAllERC20ToSafeAddress(
                MainnetAddresses.VOLT_DAI_PSM,
                MainnetAddresses.VOLT
            );

        uint256 governorVoltBalanceAfterDai = IERC20(MainnetAddresses.VOLT)
            .balanceOf(MainnetAddresses.GOVERNOR);

        voltInDaiPSM =
            governorVoltBalanceAfterDai -
            governorVoltBalanceBeforeDai;

        // pull out DAI from VOLT-DAI PSM to Governor

        uint256 governorDaiBalanceBeforeDai = IERC20(MainnetAddresses.DAI)
            .balanceOf(MainnetAddresses.GOVERNOR);

        PCVGuardian(MainnetAddresses.PCV_GUARDIAN)
            .withdrawAllERC20ToSafeAddress(
                MainnetAddresses.VOLT_DAI_PSM,
                MainnetAddresses.DAI
            );

        uint256 governorDaiBalanceAfterDai = IERC20(MainnetAddresses.DAI)
            .balanceOf(MainnetAddresses.GOVERNOR);

        daiInDaiPSM = governorDaiBalanceAfterDai - governorDaiBalanceBeforeDai;

        IERC20(MainnetAddresses.VOLT).transfer(
            MainnetAddresses.TIMELOCK_CONTROLLER,
            voltInDaiPSM + voltInUsdcPSM
        );
        IERC20(MainnetAddresses.DAI).transfer(
            MainnetAddresses.TIMELOCK_CONTROLLER,
            daiInDaiPSM
        );
        IERC20(MainnetAddresses.USDC).transfer(
            MainnetAddresses.TIMELOCK_CONTROLLER,
            usdcInUsdcPSM
        );
        vm.stopPrank();
    }

    function mainnetValidate() public override {
        // Volt Token Validations
        assertEq(voltV2.decimals(), 18);
        assertEq(voltV2.symbol(), "VOLT");
        assertEq(voltV2.name(), "Volt");
        assertEq(voltV2.totalSupply(), oldVoltTotalSupply);
        assertEq(address(voltV2.core()), MainnetAddresses.CORE);

        // Volt Migrator Validations
        assertEq(address(voltMigrator.core()), MainnetAddresses.CORE);
        assertEq(address(voltMigrator.OLD_VOLT()), MainnetAddresses.VOLT);
        assertEq(address(voltMigrator.newVolt()), address(voltV2));
        assertEq(
            IERC20(address(voltV2)).balanceOf(address(voltMigrator)),
            oldVoltTotalSupply - (voltInUsdcPSM + voltInDaiPSM)
        );

        // Migrator Router Validations
        assertEq(
            address(migratorRouter.daiPSM()),
            address(voltV2DaiPriceBoundPSM)
        );
        assertEq(
            address(migratorRouter.usdcPSM()),
            address(voltV2UsdcPriceBoundPSM)
        );
        assertEq(address(migratorRouter.voltMigrator()), address(voltMigrator));
        assertEq(address(migratorRouter.newVolt()), address(voltV2));
        assertEq(address(migratorRouter.OLD_VOLT()), MainnetAddresses.VOLT);

        // New USDC PriceBoundPSM validations
        assertTrue(voltV2UsdcPriceBoundPSM.doInvert());
        assertTrue(voltV2UsdcPriceBoundPSM.isPriceValid());
        assertEq(voltV2UsdcPriceBoundPSM.floor(), voltUsdcFloorPrice);
        assertEq(voltV2UsdcPriceBoundPSM.ceiling(), voltUsdcCeilingPrice);
        assertEq(
            address(voltV2UsdcPriceBoundPSM.oracle()),
            address(MainnetAddresses.ORACLE_PASS_THROUGH)
        );
        assertEq(address(voltV2UsdcPriceBoundPSM.backupOracle()), address(0));
        assertEq(voltV2UsdcPriceBoundPSM.decimalsNormalizer(), 12);
        assertEq(voltV2UsdcPriceBoundPSM.mintFeeBasisPoints(), 0);
        assertEq(voltV2UsdcPriceBoundPSM.redeemFeeBasisPoints(), 0);
        assertEq(
            address(voltV2UsdcPriceBoundPSM.underlyingToken()),
            MainnetAddresses.USDC
        );
        assertEq(address(voltV2UsdcPriceBoundPSM.surplusTarget()), address(1));
        assertEq(
            voltV2UsdcPriceBoundPSM.reservesThreshold(),
            type(uint256).max
        );
        assertEq(address(voltV2UsdcPriceBoundPSM.volt()), address(voltV2));
        assertEq(
            voltV2.balanceOf(address(voltV2UsdcPriceBoundPSM)),
            voltInUsdcPSM
        );
        assertEq(
            IERC20(MainnetAddresses.USDC).balanceOf(
                address(voltV2UsdcPriceBoundPSM)
            ),
            usdcInUsdcPSM
        );

        // New DAI PriceBoundPSM validations
        assertTrue(voltV2DaiPriceBoundPSM.doInvert());
        assertTrue(voltV2DaiPriceBoundPSM.isPriceValid());
        assertEq(voltV2DaiPriceBoundPSM.floor(), voltDaiFloorPrice);
        assertEq(voltV2DaiPriceBoundPSM.ceiling(), voltDaiCeilingPrice);
        assertEq(
            address(voltV2DaiPriceBoundPSM.oracle()),
            address(MainnetAddresses.ORACLE_PASS_THROUGH)
        );
        assertEq(address(voltV2DaiPriceBoundPSM.backupOracle()), address(0));
        assertEq(voltV2DaiPriceBoundPSM.decimalsNormalizer(), 0);
        assertEq(voltV2DaiPriceBoundPSM.mintFeeBasisPoints(), 0);
        assertEq(voltV2DaiPriceBoundPSM.redeemFeeBasisPoints(), 0);
        assertEq(
            address(voltV2DaiPriceBoundPSM.underlyingToken()),
            address(MainnetAddresses.DAI)
        );
        assertEq(voltV2DaiPriceBoundPSM.reservesThreshold(), type(uint256).max);
        assertEq(address(voltV2DaiPriceBoundPSM.surplusTarget()), address(1));
        assertEq(address(voltV2DaiPriceBoundPSM.volt()), address(voltV2));
        assertEq(
            voltV2.balanceOf(address(voltV2DaiPriceBoundPSM)),
            voltInDaiPSM
        );
        assertEq(
            IERC20(MainnetAddresses.USDC).balanceOf(
                address(voltV2DaiPriceBoundPSM)
            ),
            daiInDaiPSM
        );

        /// assert erc20 allocator has usdc psm and pcv deposit connected
        {
            address psmAddress = allocator.pcvDepositToPSM(address(daiDeposit));
            assertEq(psmAddress, address(voltV2DaiPriceBoundPSM));
        }

        /// assert erc20 allocator has dai psm and pcv deposit connected
        {
            address psmAddress = allocator.pcvDepositToPSM(
                address(usdcDeposit)
            );
            assertEq(psmAddress, address(voltV2UsdcPriceBoundPSM));
        }

        /// assert decimal normalization and target balances are correct for both dai and usdc
        {
            (
                address psmToken,
                uint248 psmTargetBalance,
                int8 decimalsNormalizer
            ) = allocator.allPSMs(address(voltV2UsdcPriceBoundPSM));
            assertEq(psmToken, MainnetAddresses.USDC);
            assertEq(psmTargetBalance, targetBalanceUsdc);
            assertEq(decimalsNormalizer, usdcDecimalNormalizer);
        }
        {
            (
                address psmToken,
                uint248 psmTargetBalance,
                int8 decimalsNormalizer
            ) = allocator.allPSMs(address(voltV2DaiPriceBoundPSM));
            assertEq(psmToken, MainnetAddresses.DAI);
            assertEq(psmTargetBalance, targetBalanceDai);
            assertEq(decimalsNormalizer, daiDecimalNormalizer);
        }
        /// assert that DAI PSM and USDC PSM are whitelisted in PCV Guardian
        assertTrue(
            PCVGuardian(MainnetAddresses.PCV_GUARDIAN).isWhitelistAddress(
                address(voltV2UsdcPriceBoundPSM)
            )
        );

        assertTrue(
            PCVGuardian(MainnetAddresses.PCV_GUARDIAN).isWhitelistAddress(
                address(voltV2DaiPriceBoundPSM)
            )
        );
    }

    /// prevent errors by reverting on arbitrum proposal functions being called on this VIP
    function getArbitrumProposal()
        public
        pure
        override
        returns (ITimelockSimulation.action[] memory)
    {
        revert("no arbitrum proposal");
    }

    function arbitrumSetup() public override {
        revert("no arbitrum proposal");
    }

    function arbitrumValidate() public override {
        revert("no arbitrum proposal");
    }

    function deployPsms(address _voltV2) internal {
        PegStabilityModule.OracleParams memory oracleParamsDai;
        PegStabilityModule.OracleParams memory oracleParamsUsdc;

        oracleParamsDai = PegStabilityModule.OracleParams({
            coreAddress: address(MainnetAddresses.CORE),
            oracleAddress: address(MainnetAddresses.ORACLE_PASS_THROUGH),
            backupOracle: address(0),
            decimalsNormalizer: 0,
            doInvert: true,
            volt: IVolt(_voltV2)
        });

        oracleParamsUsdc = PegStabilityModule.OracleParams({
            coreAddress: address(MainnetAddresses.CORE),
            oracleAddress: address(MainnetAddresses.ORACLE_PASS_THROUGH),
            backupOracle: address(0),
            decimalsNormalizer: 12,
            doInvert: true,
            volt: IVolt(_voltV2)
        });

        voltV2DaiPriceBoundPSM = new PriceBoundPSM(
            voltDaiFloorPrice,
            voltDaiCeilingPrice,
            oracleParamsDai,
            0,
            0,
            // the next 3 values are garbage values as
            // psms are no longer given the minter role to mint
            type(uint256).max,
            10_000e18,
            10_000_000e18,
            IERC20(address(MainnetAddresses.DAI)),
            IPCVDeposit(address(1))
        );

        voltV2UsdcPriceBoundPSM = new PriceBoundPSM(
            voltUsdcFloorPrice,
            voltUsdcCeilingPrice,
            oracleParamsUsdc,
            0,
            0,
            // the next 3 values are garbage values as
            // psms are no longer given the minter role to mint
            type(uint256).max,
            10_000e18,
            10_000_000e18,
            IERC20(address(MainnetAddresses.USDC)),
            IPCVDeposit(address(1))
        );
    }
}
