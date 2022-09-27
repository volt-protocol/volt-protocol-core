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
import {VoltMigrator} from "../../../volt/VoltMigrator.sol";
import {VoltV2} from "../../../volt/VoltV2.sol";
import {IVolt} from "../../../volt/IVolt.sol";
import {IPCVDeposit} from "../../../pcv/IPCVDeposit.sol";

contract vip13 is DSTest, IVIP {
    using SafeERC20 for IERC20;
    Vm public constant vm = Vm(HEVM_ADDRESS);
    uint256 voltInUsdcPSM;
    uint256 voltInDaiPSM;

    PriceBoundPSM public voltV2DaiPriceBoundPSM;
    PriceBoundPSM public voltV2UsdcPriceBoundPSM;

    VoltV2 public voltV2;

    VoltMigrator public voltMigrator;

    ITimelockSimulation.action[] private proposal;

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
    ERC20CompoundPCVDeposit private feiDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_FEI_PCV_DEPOSIT);
    ERC20CompoundPCVDeposit private usdcDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT);

    constructor() {
        voltV2 = new VoltV2(MainnetAddresses.CORE);
        voltMigrator = new VoltMigrator(MainnetAddresses.CORE, address(voltV2));
        deployPsms(address(voltV2));

        address[] memory toWhitelist = new address[](2);
        toWhitelist[0] = address(voltV2UsdcPriceBoundPSM);
        toWhitelist[1] = address(voltV2DaiPriceBoundPSM);

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: address(voltMigrator),
                arguments: abi.encodeWithSignature(
                    "exchangeTo(address,uint256)",
                    address(voltV2UsdcPriceBoundPSM),
                    voltInUsdcPSM
                ),
                description: "Mint new volt for new USDC PSM"
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
                description: "Mint new volt for new DAI PSM"
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
                description: "Disconnect USDC PSM from the ERC20 Allocator"
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
                description: "Disconnect DAI PSM from the ERC20 Allocator"
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
                description: "Add USDC PSM to the ERC20 Allocator"
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
                description: "Add DAI PSM to the ERC20 Allocator"
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
                description: "Whitelist new PSMs on PCV Guardian"
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
        // new pcv guardian to be deployed with safe address as timelock
        uint256 governorVoltBalanceBeforeUsdc = IERC20(MainnetAddresses.VOLT)
            .balanceOf(MainnetAddresses.GOVERNOR);

        vm.startPrank(MainnetAddresses.GOVERNOR);

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

        IERC20(MainnetAddresses.VOLT).transfer(
            MainnetAddresses.TIMELOCK_CONTROLLER,
            voltInDaiPSM + voltInUsdcPSM
        );

        Core(MainnetAddresses.CORE).grantMinter(MainnetAddresses.GOVERNOR);
        VoltV2(address(voltV2)).mint(
            address(voltMigrator),
            voltInDaiPSM + voltInUsdcPSM
        );
        Core(MainnetAddresses.CORE).revokeMinter(MainnetAddresses.GOVERNOR);
        vm.stopPrank();
    }

    function mainnetValidate() public override {
        // currently commented as new PSMs not deployed so will not compile
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

        uint256 voltDaiFloorPrice = 9_000;
        uint256 voltDaiCeilingPrice = 10_000;

        uint256 voltUsdcFloorPrice = 9_000e12;
        uint256 voltUsdcCeilingPrice = 10_000e12;

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
            decimalsNormalizer: 0,
            doInvert: true,
            volt: IVolt(_voltV2)
        });

        voltV2DaiPriceBoundPSM = new PriceBoundPSM(
            voltDaiFloorPrice,
            voltDaiCeilingPrice,
            oracleParamsDai,
            0,
            0,
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
            type(uint256).max,
            10_000e18,
            10_000_000e18,
            IERC20(address(MainnetAddresses.USDC)),
            IPCVDeposit(address(1))
        );
    }
}
