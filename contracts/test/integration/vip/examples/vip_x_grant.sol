pragma solidity =0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {TimelockSimulation} from "../../utils/TimelockSimulation.sol";
import {ArbitrumAddresses} from "../../fixtures/ArbitrumAddresses.sol";
import {MainnetAddresses} from "../../fixtures/MainnetAddresses.sol";
import {PriceBoundPSM} from "../../../../peg/PriceBoundPSM.sol";
import {AllRoles} from "./../../utils/AllRoles.sol";
import {DSTest} from "./../../../unit/utils/DSTest.sol";
import {Core} from "../../../../core/Core.sol";
import {Volt} from "../../../../volt/Volt.sol";
import {IVIP} from "./../IVIP.sol";
import {Vm} from "./../../../unit/utils/Vm.sol";

contract vip_x_grant is DSTest, IVIP {
    using SafeCast for *;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    /// --------------- Mainnet ---------------

    /// this is an example proposal that will fail the PCV Guardian whitelist test
    /// as PCV is being transferrred to a non authorized smart contract
    function getMainnetProposal()
        public
        pure
        override
        returns (TimelockSimulation.action[] memory proposal)
    {
        proposal = new TimelockSimulation.action[](1);

        proposal[0].target = MainnetAddresses.CORE;
        proposal[0].value = 0;
        proposal[0].arguments = abi.encodeWithSignature(
            "grantPCVController(address)",
            MainnetAddresses.REVOKED_EOA_1
        );
        proposal[0]
            .description = "Grant PCV Controller and not setting in whitelist of PCV Guardian fails preflight checks";
    }

    function mainnetValidate() public override {}

    function mainnetSetup() public override {}

    /// --------------- Arbitrum ---------------

    function getArbitrumProposal()
        public
        pure
        override
        returns (TimelockSimulation.action[] memory proposal)
    {}

    function arbitrumSetup() public override {}

    function arbitrumValidate() public override {}
}
