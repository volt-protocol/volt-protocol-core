pragma solidity =0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ITimelockSimulation} from "../utils/ITimelockSimulation.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {ArbitrumAddresses} from "../fixtures/ArbitrumAddresses.sol";
import {DSTest} from "./../../unit/utils/DSTest.sol";
import {Core} from "../../../core/Core.sol";
import {Vm} from "./../../unit/utils/Vm.sol";
import {IVIP} from "./IVIP.sol";
import {AllRoles} from "./../utils/AllRoles.sol";

contract vip4 is DSTest, IVIP, AllRoles {
    Vm public constant vm = Vm(HEVM_ADDRESS);

    function getMainnetProposal()
        public
        pure
        override
        returns (ITimelockSimulation.action[] memory proposal)
    {
        proposal = new ITimelockSimulation.action[](8);

        proposal[0].target = MainnetAddresses.PCV_GUARD_ADMIN;
        proposal[0].value = 0;
        proposal[0].arguments = abi.encodeWithSignature(
            "revokePCVGuardRole(address)",
            MainnetAddresses.REVOKED_EOA_1
        );
        proposal[0]
            .description = "Revoke PCV Guard role from revoked EOA1 by calling PCVGuardAdmin";

        proposal[1].target = MainnetAddresses.CORE;
        proposal[1].value = 0;
        proposal[1].arguments = abi.encodeWithSignature(
            "revokeGuardian(address)",
            MainnetAddresses.EOA_1
        );
        proposal[1].description = "Revoke EOA1 as a guardian";

        proposal[2].target = MainnetAddresses.CORE;
        proposal[2].value = 0;
        proposal[2].arguments = abi.encodeWithSignature(
            "revokeMinter(address)",
            MainnetAddresses.GRLM
        );
        proposal[2]
            .description = "Revoke Global Rate Limited Minter's mint capability";

        proposal[3].target = MainnetAddresses.CORE;
        proposal[3].value = 0;
        proposal[3].arguments = abi.encodeWithSignature(
            "revokePCVController(address)",
            MainnetAddresses.NC_PSM
        );
        proposal[3]
            .description = "Revoke Non Custodial PSM PCV Controller role";

        proposal[4].target = MainnetAddresses.CORE;
        proposal[4].value = 0;
        proposal[4].arguments = abi.encodeWithSignature(
            "revokeGuardian(address)",
            MainnetAddresses.GOVERNOR
        );
        proposal[4].description = "Revoke Guardian Role from Multisig";

        proposal[5].target = MainnetAddresses.PCV_GUARD_ADMIN;
        proposal[5].value = 0;
        proposal[5].arguments = abi.encodeWithSignature(
            "grantPCVGuardRole(address)",
            MainnetAddresses.EOA_1
        );
        proposal[5].description = "Grant EOA 1 PCV Guard Role";

        proposal[6].target = MainnetAddresses.PCV_GUARD_ADMIN;
        proposal[6].value = 0;
        proposal[6].arguments = abi.encodeWithSignature(
            "grantPCVGuardRole(address)",
            MainnetAddresses.EOA_2
        );
        proposal[6].description = "Grant EOA 2 PCV Guard Role";

        proposal[7].target = MainnetAddresses.PCV_GUARD_ADMIN;
        proposal[7].value = 0;
        proposal[7].arguments = abi.encodeWithSignature(
            "grantPCVGuardRole(address)",
            MainnetAddresses.EOA_3
        );
        proposal[7].description = "Grant EOA 3 PCV Guard Role";
    }

    function mainnetSetup() public override {
        vm.prank(MainnetAddresses.GOVERNOR);
        Core(MainnetAddresses.CORE).grantGovernor(
            MainnetAddresses.TIMELOCK_CONTROLLER
        );
    }

    /// assert all contracts have their correct number of roles now,
    /// and that the proper addresses have the correct role after the governance upgrade
    function mainnetValidate() public override {
        _setupMainnet(Core(MainnetAddresses.CORE));
        testRoleArity();

        _setupMainnet(Core(MainnetAddresses.CORE));
        testRoleAddresses(Core(MainnetAddresses.CORE));
    }

    function getArbitrumProposal()
        public
        pure
        override
        returns (ITimelockSimulation.action[] memory proposal)
    {
        proposal = new ITimelockSimulation.action[](6);

        /// Role revocations
        proposal[0].target = ArbitrumAddresses.PCV_GUARD_ADMIN;
        proposal[0].value = 0;
        proposal[0].arguments = abi.encodeWithSignature(
            "revokePCVGuardRole(address)",
            ArbitrumAddresses.REVOKED_EOA_1
        );
        proposal[0]
            .description = "Revoke PCV Guard role from revoked EOA1 by calling PCVGuardAdmin";

        proposal[1].target = ArbitrumAddresses.CORE;
        proposal[1].value = 0;
        proposal[1].arguments = abi.encodeWithSignature(
            "revokeGuardian(address)",
            ArbitrumAddresses.EOA_1
        );
        proposal[1].description = "Revoke EOA1 as a guardian";

        proposal[2].target = ArbitrumAddresses.CORE;
        proposal[2].value = 0;
        proposal[2].arguments = abi.encodeWithSignature(
            "revokePCVController(address)",
            ArbitrumAddresses.DEPRECATED_TIMELOCK
        );
        proposal[2]
            .description = "Revoke Deprecated Timelock's PCV Controller role";

        /// Role additions
        proposal[3].target = ArbitrumAddresses.PCV_GUARD_ADMIN;
        proposal[3].value = 0;
        proposal[3].arguments = abi.encodeWithSignature(
            "grantPCVGuardRole(address)",
            ArbitrumAddresses.EOA_1
        );
        proposal[3].description = "Grant EOA 1 PCV Guard Role";

        proposal[4].target = ArbitrumAddresses.PCV_GUARD_ADMIN;
        proposal[4].value = 0;
        proposal[4].arguments = abi.encodeWithSignature(
            "grantPCVGuardRole(address)",
            ArbitrumAddresses.EOA_2
        );
        proposal[4].description = "Grant EOA 2 PCV Guard Role";

        proposal[5].target = ArbitrumAddresses.PCV_GUARD_ADMIN;
        proposal[5].value = 0;
        proposal[5].arguments = abi.encodeWithSignature(
            "grantPCVGuardRole(address)",
            ArbitrumAddresses.EOA_3
        );
        proposal[5].description = "Grant EOA 3 PCV Guard Role";
    }

    function arbitrumSetup() public override {
        vm.prank(ArbitrumAddresses.GOVERNOR);
        Core(ArbitrumAddresses.CORE).grantGovernor(
            ArbitrumAddresses.TIMELOCK_CONTROLLER
        );
    }

    /// assert all contracts have their correct number of roles now,
    /// and that the proper addresses have the correct role after the governance upgrade
    function arbitrumValidate() public override {
        _setupArbitrum(Core(ArbitrumAddresses.CORE));
        testRoleArity();

        _setupArbitrum(Core(ArbitrumAddresses.CORE));
        testRoleAddresses(Core(ArbitrumAddresses.CORE));
    }
}
