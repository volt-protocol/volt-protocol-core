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
import {Volt} from "../../../volt/Volt.sol";

contract vip5 is DSTest, IVIP, AllRoles {
    Vm public constant vm = Vm(HEVM_ADDRESS);

    uint256 constant voltBalance = 10_000_000e18;

    function getMainnetProposal()
        public
        pure
        override
        returns (ITimelockSimulation.action[] memory proposal)
    {
        proposal = new ITimelockSimulation.action[](1);

        proposal[0].target = MainnetAddresses.VOLT;
        proposal[0].value = 0;
        proposal[0].arguments = abi.encodeWithSignature(
            "burn(uint256)",
            voltBalance
        );
        proposal[0].description = "Burn 10m VOLT in deprecated timelock";
    }

    function mainnetSetup() public override {}

    /// assert all contracts have their correct number of roles now,
    /// and that the proper addresses have the correct role after the governance upgrade
    function mainnetValidate() public override {
        uint256 deprecatedTimelockVoltBalance = Volt(MainnetAddresses.VOLT)
            .balanceOf(MainnetAddresses.VOLT_TIMELOCK);

        assertEq(deprecatedTimelockVoltBalance, 0);
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
        if (false) {
            roleToName[bytes32(0)] = "";
        }
        revert("no arbitrum proposal");
    }

    function arbitrumValidate() public override {
        if (false) {
            roleToName[bytes32(0)] = "";
        }
        revert("no arbitrum proposal");
    }
}
