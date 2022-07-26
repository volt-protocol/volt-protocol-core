pragma solidity =0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {TimelockSimulation} from "../utils/TimelockSimulation.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {DSTest} from "./../../unit/utils/DSTest.sol";
import {Core} from "../../../core/Core.sol";
import {Vm} from "./../../unit/utils/Vm.sol";

import "hardhat/console.sol";

contract vip4 is DSTest {
    Vm public constant vm = Vm(HEVM_ADDRESS);

    function getVIP()
        public
        pure
        returns (TimelockSimulation.action[] memory proposal)
    {
        proposal = new TimelockSimulation.action[](7);

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

        proposal[4].target = MainnetAddresses.PCV_GUARD_ADMIN;
        proposal[4].value = 0;
        proposal[4].arguments = abi.encodeWithSignature(
            "grantPCVGuardRole(address)",
            MainnetAddresses.EOA_1
        );
        proposal[4].description = "Grant EOA 1 PCV Guard Role";

        proposal[5].target = MainnetAddresses.PCV_GUARD_ADMIN;
        proposal[5].value = 0;
        proposal[5].arguments = abi.encodeWithSignature(
            "grantPCVGuardRole(address)",
            MainnetAddresses.EOA_2
        );
        proposal[5].description = "Grant EOA 2 PCV Guard Role";

        proposal[6].target = MainnetAddresses.PCV_GUARD_ADMIN;
        proposal[6].value = 0;
        proposal[6].arguments = abi.encodeWithSignature(
            "grantPCVGuardRole(address)",
            MainnetAddresses.EOA_3
        );
        proposal[6].description = "Grant EOA 3 PCV Guard Role";
    }

    function setup() internal {
        vm.prank(MainnetAddresses.GOVERNOR);
        Core(MainnetAddresses.CORE).grantGovernor(
            MainnetAddresses.TIMELOCK_CONTROLLER
        );
    }

    function testPrintScheduleAndExecuteCalldata() public {
        uint256 delay = TimelockController(
            payable(MainnetAddresses.TIMELOCK_CONTROLLER)
        ).getMinDelay();
        bytes32 salt = bytes32(0);
        bytes32 predecessor = bytes32(0);

        TimelockSimulation.action[] memory proposal = getVIP();

        uint256 proposalLength = proposal.length;
        address[] memory targets = new address[](proposalLength);
        uint256[] memory values = new uint256[](proposalLength);
        bytes[] memory payloads = new bytes[](proposalLength);

        for (uint256 i = 0; i < proposalLength; i++) {
            targets[i] = proposal[i].target;
            values[i] = proposal[i].value;
            payloads[i] = proposal[i].arguments;
        }

        console.log("schedule batch calldata");
        emit log_bytes(
            abi.encodeWithSignature(
                "scheduleBatch(address[],uint256[],bytes[],bytes32,bytes32,uint256)",
                targets,
                values,
                payloads,
                predecessor,
                salt,
                delay
            )
        );

        console.log("execute batch calldata");
        emit log_bytes(
            abi.encodeWithSignature(
                "executeBatch(address[],uint256[],bytes[],bytes32,bytes32)",
                targets,
                values,
                payloads,
                predecessor,
                salt
            )
        );
    }
}
