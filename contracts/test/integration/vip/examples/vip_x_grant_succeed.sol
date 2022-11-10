pragma solidity =0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {Vm} from "./../../../unit/utils/Vm.sol";
import {IVIP} from "./../IVIP.sol";
import {Volt} from "../../../../volt/Volt.sol";
import {Core} from "../../../../core/Core.sol";
import {DSTest} from "./../../../unit/utils/DSTest.sol";
import {AllRoles} from "./../../utils/AllRoles.sol";
import {MainnetAddresses} from "../../fixtures/MainnetAddresses.sol";
import {ArbitrumAddresses} from "../../fixtures/ArbitrumAddresses.sol";
import {ITimelockSimulation} from "../../utils/ITimelockSimulation.sol";

contract vip_x_grant_succeed is DSTest, IVIP {
    using SafeCast for *;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    /// --------------- Mainnet ---------------

    /// this is an example proposal that will fail the PCV Guardian whitelist test
    /// as PCV is being transferrred to a non authorized smart contract
    function getMainnetProposal()
        public
        pure
        override
        returns (ITimelockSimulation.action[] memory proposal)
    {
        proposal = new ITimelockSimulation.action[](2);

        proposal[0].target = MainnetAddresses.CORE;
        proposal[0].value = 0;
        proposal[0].arguments = abi.encodeWithSignature(
            "grantPCVController(address)",
            MainnetAddresses.GOVERNOR
        );
        proposal[0].description = "Grant PCV Controller";

        proposal[1].target = MainnetAddresses.PCV_GUARDIAN;
        proposal[1].value = 0;
        proposal[1].arguments = abi.encodeWithSignature(
            "addWhitelistAddress(address)",
            MainnetAddresses.GOVERNOR
        );
        proposal[1].description = "Add governor to whitelist in PCV Guardian";
    }

    function mainnetValidate() public override {}

    function mainnetSetup() public override {}

    /// --------------- Arbitrum ---------------

    function getArbitrumProposal()
        public
        pure
        override
        returns (ITimelockSimulation.action[] memory proposal)
    {}

    function arbitrumSetup() public override {}

    function arbitrumValidate() public override {}
}
