//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Vm} from "./../../unit/utils/Vm.sol";
import {IVIP} from "./IVIP.sol";
import {Core} from "../../../core/Core.sol";
import {IVolt} from "../../../volt/IVolt.sol";
import {DSTest} from "./../../unit/utils/DSTest.sol";
import {VoltV2} from "../../../volt/VoltV2.sol";
import {VoltRoles} from "../../../core/VoltRoles.sol";
import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";
import {IPCVDeposit} from "../../../pcv/IPCVDeposit.sol";
import {VoltMigrator} from "../../../volt/VoltMigrator.sol";
import {IVoltMigrator} from "../../../volt/IVoltMigrator.sol";
import {ERC20Allocator} from "../../../pcv/utils/ERC20Allocator.sol";
import {MigratorRouter} from "../../../pcv/MigratorRouter.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";
import {IPegStabilityModule} from "../../../peg/IPegStabilityModule.sol";
import {ITimelockSimulation} from "../utils/ITimelockSimulation.sol";
import {ERC20CompoundPCVDeposit} from "../../../pcv/compound/ERC20CompoundPCVDeposit.sol";

import {console} from "hardhat/console.sol";

contract vip15 is DSTest, IVIP {
    using SafeERC20 for IERC20;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    /// timelock controller roles
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");

    /// old core
    bytes32 public constant PCV_GUARD_ADMIN_ROLE =
        keccak256("PCV_GUARD_ADMIN_ROLE");
    bytes32 public constant GOVERN_ROLE = keccak256("GOVERN_ROLE");

    PegStabilityModule public daiPriceBoundPSM =
        PegStabilityModule(MainnetAddresses.VOLT_DAI_PSM);
    PegStabilityModule public usdcPriceBoundPSM =
        PegStabilityModule(MainnetAddresses.VOLT_USDC_PSM);

    Core public core = Core(MainnetAddresses.CORE);
    VoltV2 public voltV2;
    IVolt public oldVolt = IVolt(MainnetAddresses.VOLT);

    VoltMigrator public voltMigrator;
    MigratorRouter public migratorRouter;

    ITimelockSimulation.action[] private proposal;

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

        /// ------- poker morpho to update p2p indexes -------

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.MORPHO,
                arguments: abi.encodeWithSignature(
                    "updateP2PIndexes(address)",
                    MainnetAddresses.CDAI
                ),
                description: "Accrue interest in Morpho CDAI market"
            })
        );

        /// ------- withdraw funds from morpho -------

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.PCV_GUARDIAN,
                arguments: abi.encodeWithSignature(
                    "withdrawAllToSafeAddress(address)",
                    MainnetAddresses.MORPHO_COMPOUND_DAI_PCV_DEPOSIT
                ),
                description: "Withdraw all DAI from Morpho Compound PCV Deposit"
            })
        );

        /// usdc deposit has no balance, withdrawing when balance is 0 reverts on morpho
        /// so comment out this part of proposal so it can pass
        // proposal.push(
        //     ITimelockSimulation.action({
        //         value: 0,
        //         target: MainnetAddresses.PCV_GUARDIAN,
        //         arguments: abi.encodeWithSignature(
        //             "withdrawAllToSafeAddress(address)",
        //             MainnetAddresses.MORPHO_COMPOUND_USDC_PCV_DEPOSIT
        //         ),
        //         description: "Withdraw all USDC from Morpho Compound PCV Deposit"
        //     })
        // );

        /// ------- withdraw funds from psms -------

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.PCV_GUARDIAN,
                arguments: abi.encodeWithSignature(
                    "withdrawAllToSafeAddress(address)",
                    MainnetAddresses.VOLT_DAI_PSM
                ),
                description: "Withdraw all DAI from PSM"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.PCV_GUARDIAN,
                arguments: abi.encodeWithSignature(
                    "withdrawAllToSafeAddress(address)",
                    MainnetAddresses.VOLT_USDC_PSM
                ),
                description: "Withdraw all USDC from PSM"
            })
        );

        /// ------- withdraw volt from psms -------

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.PCV_GUARDIAN,
                arguments: abi.encodeWithSignature(
                    "withdrawAllERC20ToSafeAddress(address,address)",
                    MainnetAddresses.VOLT_DAI_PSM,
                    MainnetAddresses.VOLT
                ),
                description: "Withdraw all VOLT from DAI PSM"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.PCV_GUARDIAN,
                arguments: abi.encodeWithSignature(
                    "withdrawAllERC20ToSafeAddress(address,address)",
                    MainnetAddresses.VOLT_USDC_PSM,
                    MainnetAddresses.VOLT
                ),
                description: "Withdraw all VOLT from USDC PSM"
            })
        );

        /// ------- pause morpho deposits -------

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.MORPHO_COMPOUND_USDC_PCV_DEPOSIT,
                arguments: abi.encodeWithSignature("pause()"),
                description: "Pause USDC Morpho Compound PCV Deposit"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.MORPHO_COMPOUND_DAI_PCV_DEPOSIT,
                arguments: abi.encodeWithSignature("pause()"),
                description: "Pause USDC Morpho Compound PCV Deposit"
            })
        );

        /// ------- pause psms -------

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.VOLT_USDC_PSM,
                arguments: abi.encodeWithSignature("pause()"),
                description: "Pause USDC PSM"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.VOLT_DAI_PSM,
                arguments: abi.encodeWithSignature("pause()"),
                description: "Pause DAI PSM"
            })
        );

        /// ------- pause allocator -------

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.ERC20ALLOCATOR,
                arguments: abi.encodeWithSignature("pause()"),
                description: "Pause ERC20 Allocator"
            })
        );

        /// ------- role revoked in core -------

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.CORE,
                arguments: abi.encodeWithSignature(
                    "revokePCVController(address)",
                    MainnetAddresses.MORPHO_COMPOUND_PCV_ROUTER
                ),
                description: "Revoke PCV Controller from Morpho Compound PCV Router"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.CORE,
                arguments: abi.encodeWithSignature(
                    "revokePCVController(address)",
                    MainnetAddresses.ERC20ALLOCATOR
                ),
                description: "Revoke PCV Controller from ERC20 Allocator"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.CORE,
                arguments: abi.encodeWithSignature(
                    "revokeGovernor(address)",
                    MainnetAddresses.GOVERNOR
                ),
                description: "Revoke PCV Controller from ERC20 Allocator"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.CORE,
                arguments: abi.encodeWithSignature(
                    "revokePCVController(address)",
                    MainnetAddresses.PCV_GUARDIAN
                ),
                description: "Revoke PCV Controller from PCV_GUARDIAN"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.CORE,
                arguments: abi.encodeWithSignature(
                    "revokePCVController(address)",
                    MainnetAddresses.GOVERNOR
                ),
                description: "Revoke PCV Controller from multisig"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.CORE,
                arguments: abi.encodeWithSignature(
                    "revokeGuardian(address)",
                    MainnetAddresses.PCV_GUARDIAN
                ),
                description: "Revoke Guardian from PCV_GUARDIAN"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.PCV_GUARD_ADMIN,
                arguments: abi.encodeWithSignature(
                    "revokePCVGuardRole(address)",
                    MainnetAddresses.EOA_1
                ),
                description: "Revoke PCV_GUARD from EOA_1"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.PCV_GUARD_ADMIN,
                arguments: abi.encodeWithSignature(
                    "revokePCVGuardRole(address)",
                    MainnetAddresses.EOA_2
                ),
                description: "Revoke Guardian from EOA_2"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.PCV_GUARD_ADMIN,
                arguments: abi.encodeWithSignature(
                    "revokePCVGuardRole(address)",
                    MainnetAddresses.EOA_4
                ),
                description: "Revoke PCV_GUARD from EOA_4"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.CORE,
                arguments: abi.encodeWithSignature(
                    "revokeRole(bytes32,address)",
                    PCV_GUARD_ADMIN_ROLE,
                    MainnetAddresses.PCV_GUARD_ADMIN
                ),
                description: "Revoke PCV Guard Admin from PCV_GUARD_ADMIN"
            })
        );

        /// ------- role revoked in timelock -------

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.TIMELOCK_CONTROLLER,
                arguments: abi.encodeWithSignature(
                    "revokeRole(bytes32,address)",
                    PROPOSER_ROLE,
                    MainnetAddresses.EOA_1
                ),
                description: "Revoke proposer role from EOA 1"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.TIMELOCK_CONTROLLER,
                arguments: abi.encodeWithSignature(
                    "revokeRole(bytes32,address)",
                    CANCELLER_ROLE,
                    MainnetAddresses.EOA_1
                ),
                description: "Revoke canceller role from EOA 1"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.TIMELOCK_CONTROLLER,
                arguments: abi.encodeWithSignature(
                    "revokeRole(bytes32,address)",
                    PROPOSER_ROLE,
                    MainnetAddresses.EOA_2
                ),
                description: "Revoke proposer role from EOA 2"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.TIMELOCK_CONTROLLER,
                arguments: abi.encodeWithSignature(
                    "revokeRole(bytes32,address)",
                    CANCELLER_ROLE,
                    MainnetAddresses.EOA_2
                ),
                description: "Revoke canceller role from EOA 2"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.TIMELOCK_CONTROLLER,
                arguments: abi.encodeWithSignature(
                    "revokeRole(bytes32,address)",
                    PROPOSER_ROLE,
                    MainnetAddresses.EOA_4
                ),
                description: "Revoke proposer role from EOA 4"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.TIMELOCK_CONTROLLER,
                arguments: abi.encodeWithSignature(
                    "revokeRole(bytes32,address)",
                    CANCELLER_ROLE,
                    MainnetAddresses.EOA_4
                ),
                description: "Revoke canceller role from EOA 4"
            })
        );

        /// ------- role granted in timelock -------

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.TIMELOCK_CONTROLLER,
                arguments: abi.encodeWithSignature(
                    "grantRole(bytes32,address)",
                    PROPOSER_ROLE,
                    MainnetAddresses.GOVERNOR
                ),
                description: "Grant proposer role to multisig"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.TIMELOCK_CONTROLLER,
                arguments: abi.encodeWithSignature(
                    "grantRole(bytes32,address)",
                    CANCELLER_ROLE,
                    MainnetAddresses.GOVERNOR
                ),
                description: "Grant canceller role to multisig"
            })
        );

        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.TIMELOCK_CONTROLLER,
                arguments: abi.encodeWithSignature(
                    "grantRole(bytes32,address)",
                    EXECUTOR_ROLE,
                    address(0)
                ),
                description: "Allow execution by any address"
            })
        );

        /// ------- disconnect psms -------

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
    }

    function getMainnetProposal()
        public
        view
        override
        returns (ITimelockSimulation.action[] memory prop)
    {
        prop = proposal;
    }

    function mainnetSetup() public override {}

    function mainnetValidate() public override {
        /// core roles
        assertEq(core.getRoleMemberCount(core.PCV_CONTROLLER_ROLE()), 0);
        assertEq(core.getRoleMemberCount(core.GUARDIAN_ROLE()), 0);
        assertEq(core.getRoleMemberCount(GOVERN_ROLE), 2);
        assertEq(core.getRoleMemberCount(core.MINTER_ROLE()), 0);
        assertEq(core.getRoleMemberCount(core.BURNER_ROLE()), 0);
        assertEq(core.getRoleMemberCount(PCV_GUARD_ADMIN_ROLE), 0);
        assertEq(core.getRoleMemberCount(VoltRoles.PCV_GUARD), 0);

        /// address role validation
        assertTrue(!core.isPCVController(address(allocator)));
        assertTrue(
            !core.isPCVController(MainnetAddresses.MORPHO_COMPOUND_PCV_ROUTER)
        );
        assertTrue(!core.isPCVController(address(allocator)));
        assertTrue(!core.isGovernor(MainnetAddresses.GOVERNOR));
        assertTrue(core.isGovernor(address(core)));
        assertTrue(core.isGovernor(MainnetAddresses.TIMELOCK_CONTROLLER));

        /// timelock roles
        TimelockController tc = TimelockController(
            payable(MainnetAddresses.TIMELOCK_CONTROLLER)
        );
        assertTrue(tc.hasRole(PROPOSER_ROLE, MainnetAddresses.GOVERNOR));
        assertTrue(tc.hasRole(CANCELLER_ROLE, MainnetAddresses.GOVERNOR));
        assertTrue(tc.hasRole(EXECUTOR_ROLE, address(0)));

        /// paused
        assertTrue(daiPriceBoundPSM.paused());
        assertTrue(usdcPriceBoundPSM.paused());

        assertTrue(daiDeposit.paused());
        assertTrue(usdcDeposit.paused());

        assertTrue(allocator.paused());

        /// pcv deposits
        assertTrue(daiDeposit.balance() < 1e18); /// less than $1 left in Morpho
        assertEq(usdcDeposit.balance(), 0);

        /// ensure msig can still propose to the timelock after the proposal

        bytes memory data = "";
        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(keccak256(abi.encodePacked(int256(123456789))));
        uint256 ethSendAmount = 100 ether;
        uint256 delay = tc.getMinDelay();

        vm.deal(address(tc), ethSendAmount);
        vm.startPrank(MainnetAddresses.GOVERNOR);
        tc.schedule(
            MainnetAddresses.GOVERNOR,
            ethSendAmount,
            data,
            predecessor,
            salt,
            delay
        );
        vm.warp(block.timestamp + delay);
        tc.execute(
            MainnetAddresses.GOVERNOR,
            ethSendAmount,
            data,
            predecessor,
            salt
        );
        vm.stopPrank();

        /// assert core is still intact and can grant roles
        vm.prank(address(tc));
        core.grantGovernor(MainnetAddresses.GOVERNOR);
        assertTrue(core.isGovernor(MainnetAddresses.GOVERNOR));
        assertEq(core.getRoleMemberCount(GOVERN_ROLE), 3);
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

    function arbitrumSetup() public pure override {
        revert("no arbitrum proposal");
    }

    function arbitrumValidate() public pure override {
        revert("no arbitrum proposal");
    }
}
