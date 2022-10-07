//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {Vm} from "./../../unit/utils/Vm.sol";
import {Core} from "../../../core/Core.sol";
import {IVIP} from "./IVIP.sol";
import {DSTest} from "./../../unit/utils/DSTest.sol";
import {PCVDeposit} from "../../../pcv/PCVDeposit.sol";
import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";
import {IPCVDeposit} from "../../../pcv/IPCVDeposit.sol";
import {PriceBoundPSM} from "../../../peg/PriceBoundPSM.sol";
import {ERC20Allocator} from "../../../pcv/utils/ERC20Allocator.sol";
import {MaplePCVDeposit} from "../../../pcv/maple/MaplePCVDeposit.sol";
import {VoltSystemOracle} from "../../../oracle/VoltSystemOracle.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {ArbitrumAddresses} from "../fixtures/ArbitrumAddresses.sol";
import {OraclePassThrough} from "../../../oracle/OraclePassThrough.sol";
import {CompoundPCVRouter} from "../../../pcv/compound/CompoundPCVRouter.sol";
import {ITimelockSimulation} from "../utils/ITimelockSimulation.sol";
import {MorphoCompoundPCVDeposit} from "../../../pcv/morpho/MorphoCompoundPCVDeposit.sol";

/// Deployment Steps
/// 1. deploy morpho dai deposit
/// 2. deploy morpho usdc deposit
/// 3. deploy compound pcv router pointed to morpho dai and usdc deposits
/// 4. deploy volt system oracle
/// 5. deploy maple usdc deposit

/// Governance Steps
/// 1. grant new PCV router PCV Controller role
/// 2. revoke PCV Controller role from old PCV Router

/// 3. disconnect old dai compound deposit from allocator
/// 4. disconnect old usdc compound deposit from allocator

/// 5. connect new dai morpho deposit to allocator
/// 6. connect new usdc morpho deposit to allocator

/// 7. add deposits as safe addresses

/// 8. connect new oracle to oracle pass through with updated rate
/// 9. Grant PCV Controller to timelock
/// 10. Deposit funds in Maple PCV Deposit
/// 11. pause dai compound pcv deposit
/// 12. pause usdc compound pcv deposit

contract vip14 is DSTest, IVIP {
    using SafeCast for uint256;
    using SafeERC20 for IERC20;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    address public immutable dai = MainnetAddresses.DAI;
    address public immutable fei = MainnetAddresses.FEI;
    address public immutable usdc = MainnetAddresses.USDC;
    address public immutable core = MainnetAddresses.CORE;

    ITimelockSimulation.action[] private mainnetProposal;
    ITimelockSimulation.action[] private arbitrumProposal;

    CompoundPCVRouter public router;
    MorphoCompoundPCVDeposit public daiDeposit;
    MorphoCompoundPCVDeposit public usdcDeposit;
    VoltSystemOracle public oracle;
    MaplePCVDeposit public mapleDeposit;

    uint256 public startTime;

    uint256 public constant monthlyChangeRateBasisPoints = 29;
    uint256 public constant arbitrumMonthlyChangeRateBasisPoints = 0;

    PCVGuardian public immutable pcvGuardian =
        PCVGuardian(MainnetAddresses.PCV_GUARDIAN);

    VoltSystemOracle private immutable oldOracle =
        VoltSystemOracle(MainnetAddresses.VOLT_SYSTEM_ORACLE_144_BIPS);

    ERC20Allocator public immutable allocator =
        ERC20Allocator(MainnetAddresses.ERC20ALLOCATOR);

    uint256 targetMapleDepositAmount = 750_000e6;

    /// --------- Maple Addresses ---------

    address public constant mplRewards =
        0x7869D7a3B074b5fa484dc04798E254c9C06A5e90;

    address public constant maplePool =
        0xFeBd6F15Df3B73DC4307B1d7E65D46413e710C27;

    constructor() {
        if (block.chainid != 1) return; /// keep ci pipeline happy
        startTime = block.timestamp + 1 days;

        mapleDeposit = new MaplePCVDeposit(core, maplePool, mplRewards);
        daiDeposit = new MorphoCompoundPCVDeposit(core, MainnetAddresses.CDAI);
        usdcDeposit = new MorphoCompoundPCVDeposit(
            core,
            MainnetAddresses.CUSDC
        );

        router = new CompoundPCVRouter(
            core,
            PCVDeposit(address(daiDeposit)),
            PCVDeposit(address(usdcDeposit))
        );

        oracle = new VoltSystemOracle(
            monthlyChangeRateBasisPoints,
            block.timestamp + 1 days,
            oldOracle.getCurrentOraclePrice()
        );

        address[] memory toWhitelist = new address[](3);
        toWhitelist[0] = address(daiDeposit);
        toWhitelist[1] = address(usdcDeposit);
        toWhitelist[2] = address(mapleDeposit);

        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.CORE,
                arguments: abi.encodeWithSignature(
                    "grantPCVController(address)",
                    address(router)
                ),
                description: "Grant Morpho PCV Router PCV Controller Role"
            })
        );
        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.CORE,
                arguments: abi.encodeWithSignature(
                    "revokePCVController(address)",
                    MainnetAddresses.COMPOUND_PCV_ROUTER
                ),
                description: "Revoke PCV Controller Role from Compound PCV Router"
            })
        );

        /// disconnect unused compound deposits
        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.ERC20ALLOCATOR,
                arguments: abi.encodeWithSignature(
                    "deleteDeposit(address)",
                    MainnetAddresses.COMPOUND_DAI_PCV_DEPOSIT
                ),
                description: "Remove Compound DAI Deposit from ERC20Allocator"
            })
        );
        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.ERC20ALLOCATOR,
                arguments: abi.encodeWithSignature(
                    "deleteDeposit(address)",
                    MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT
                ),
                description: "Remove Compound USDC Deposit from ERC20Allocator"
            })
        );

        /// connect to compound deposits
        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.ERC20ALLOCATOR,
                arguments: abi.encodeWithSignature(
                    "connectDeposit(address,address)",
                    MainnetAddresses.VOLT_DAI_PSM,
                    address(daiDeposit)
                ),
                description: "Add Morpho DAI Deposit to ERC20Allocator"
            })
        );
        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.ERC20ALLOCATOR,
                arguments: abi.encodeWithSignature(
                    "connectDeposit(address,address)",
                    MainnetAddresses.VOLT_USDC_PSM,
                    address(usdcDeposit)
                ),
                description: "Add Morpho USDC Deposit to ERC20Allocator"
            })
        );

        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.PCV_GUARDIAN,
                arguments: abi.encodeWithSignature(
                    "addWhitelistAddresses(address[])",
                    toWhitelist
                ),
                description: "Add USDC and DAI Morpho deposits and Maple deposit to the PCV Guardian"
            })
        );

        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.ORACLE_PASS_THROUGH,
                arguments: abi.encodeWithSignature(
                    "updateScalingPriceOracle(address)",
                    address(oracle)
                ),
                description: "Point Oracle Pass Through to new oracle address"
            })
        );

        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.CORE,
                arguments: abi.encodeWithSignature(
                    "grantPCVController(address)",
                    MainnetAddresses.TIMELOCK_CONTROLLER
                ),
                description: "Grant PCV Controller Role to timelock controller"
            })
        );

        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: address(mapleDeposit),
                arguments: abi.encodeWithSignature("deposit()"),
                description: "Deposit PCV into Maple"
            })
        );

        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.COMPOUND_DAI_PCV_DEPOSIT,
                arguments: abi.encodeWithSignature("pause()"),
                description: "Pause Compound DAI PCV Deposit"
            })
        );

        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT,
                arguments: abi.encodeWithSignature("pause()"),
                description: "Pause Compound USDC PCV Deposit"
            })
        );
    }

    function getMainnetProposal()
        public
        view
        override
        returns (ITimelockSimulation.action[] memory)
    {
        return mainnetProposal;
    }

    /// move all funds from compound deposits to morpho deposits
    /// move all needed funds to Maple
    function mainnetSetup() public override {
        vm.startPrank(MainnetAddresses.GOVERNOR);
        pcvGuardian.withdrawAllToSafeAddress(
            MainnetAddresses.COMPOUND_DAI_PCV_DEPOSIT
        );
        pcvGuardian.withdrawAllToSafeAddress(
            MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT
        );

        uint256 usdcBalance = IERC20(usdc).balanceOf(MainnetAddresses.GOVERNOR);
        IERC20(usdc).transfer(
            address(usdcDeposit),
            usdcBalance - targetMapleDepositAmount
        );
        IERC20(usdc).transfer(address(mapleDeposit), targetMapleDepositAmount);
        IERC20(dai).transfer(
            address(daiDeposit),
            IERC20(dai).balanceOf(MainnetAddresses.GOVERNOR)
        );

        usdcDeposit.deposit();
        daiDeposit.deposit();

        vm.stopPrank();
    }

    /// assert core addresses are set correctly
    /// assert dai and usdc compound pcv deposit are pcv guardian in whitelist
    /// assert pcv deposits are set correctly in router
    /// assert pcv deposits are set correctly in allocator
    /// assert old pcv deposits are disconnected in allocator
    /// assert oracle pass through is pointed to the proper Volt System Oracle
    function mainnetValidate() public override {
        assertEq(address(mapleDeposit.core()), core);
        assertEq(address(usdcDeposit.core()), core);
        assertEq(address(daiDeposit.core()), core);
        assertEq(address(router.core()), core);

        assertTrue(Core(core).isPCVController(address(router)));
        assertTrue(
            !Core(core).isPCVController(MainnetAddresses.COMPOUND_PCV_ROUTER)
        );

        assertTrue(pcvGuardian.isWhitelistAddress(address(daiDeposit)));
        assertTrue(pcvGuardian.isWhitelistAddress(address(usdcDeposit)));
        assertTrue(pcvGuardian.isWhitelistAddress(address(mapleDeposit)));

        /// router parameter validations
        assertEq(address(router.daiPcvDeposit()), address(daiDeposit));
        assertEq(address(router.usdcPcvDeposit()), address(usdcDeposit));
        assertEq(address(router.DAI()), dai);
        assertEq(address(router.USDC()), usdc);
        assertEq(address(router.GEM_JOIN()), MainnetAddresses.GEM_JOIN);
        assertEq(address(router.daiPSM()), MainnetAddresses.MAKER_DAI_USDC_PSM);

        /// old deposits paused
        assertTrue(
            PCVDeposit(MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT).paused()
        );
        assertTrue(
            PCVDeposit(MainnetAddresses.COMPOUND_DAI_PCV_DEPOSIT).paused()
        );

        /// old deposits disconnected in allocator
        assertEq(
            allocator.pcvDepositToPSM(
                MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT
            ),
            address(0)
        );
        assertEq(
            allocator.pcvDepositToPSM(
                MainnetAddresses.COMPOUND_DAI_PCV_DEPOSIT
            ),
            address(0)
        );

        /// new deposits connected in allocator
        assertEq(
            allocator.pcvDepositToPSM(address(daiDeposit)),
            MainnetAddresses.VOLT_DAI_PSM
        );
        assertEq(
            allocator.pcvDepositToPSM(address(usdcDeposit)),
            MainnetAddresses.VOLT_USDC_PSM
        );

        /// new pcv deposits set up correctly
        assertEq(usdcDeposit.token(), MainnetAddresses.USDC);
        assertEq(daiDeposit.token(), MainnetAddresses.DAI);

        assertEq(usdcDeposit.cToken(), MainnetAddresses.CUSDC);
        assertEq(daiDeposit.cToken(), MainnetAddresses.CDAI);

        /// oracle pass through points to new scaling price oracle
        assertEq(
            address(
                OraclePassThrough(MainnetAddresses.ORACLE_PASS_THROUGH)
                    .scalingPriceOracle()
            ),
            address(oracle)
        );

        /// volt system oracle
        /// only 1 day of interest has accrued, so only .5 basis point diff in price between old and new oracle
        assertApproxEq(
            oracle.oraclePrice().toInt256(),
            oldOracle.getCurrentOraclePrice().toInt256(),
            0
        );
        assertApproxEq(
            oracle.getCurrentOraclePrice().toInt256(),
            oldOracle.getCurrentOraclePrice().toInt256(),
            0
        );

        assertEq(
            oracle.monthlyChangeRateBasisPoints(),
            monthlyChangeRateBasisPoints
        );
        assertEq(oracle.periodStartTime(), startTime);
        assertEq(oracle.getCurrentOraclePrice(), oracle.oraclePrice());
    }

    function getArbitrumProposal()
        public
        view
        override
        returns (ITimelockSimulation.action[] memory)
    {
        revert("no arbitrum proposal");
    }

    /// no-op, nothing to setup
    function arbitrumSetup() public override {
        revert("no arbitrum proposal");
    }

    /// assert oracle pass through is pointing to correct volt system oracle
    function arbitrumValidate() public override {
        revert("no arbitrum proposal");
    }
}
