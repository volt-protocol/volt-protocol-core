pragma solidity =0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {TimelockSimulation} from "../utils/TimelockSimulation.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {DSTest} from "./../../unit/utils/DSTest.sol";
import {Core} from "../../../core/Core.sol";
import {Vm} from "./../../unit/utils/Vm.sol";
import {IVIP} from "./IVIP.sol";
import {AllRoles} from "./../utils/AllRoles.sol";
import {Volt} from "../../../volt/Volt.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";
import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";

contract vip6 is DSTest, IVIP, AllRoles {
    Vm public constant vm = Vm(HEVM_ADDRESS);

    function getMainnetProposal()
        public
        pure
        override
        returns (TimelockSimulation.action[] memory proposal)
    {
        proposal = new TimelockSimulation.action[](3);

        proposal[0].target = MainnetAddresses.VOLT_FEI_PSM;
        proposal[0].value = 0;
        proposal[0].arguments = abi.encodeWithSignature("pauseMint()");
        proposal[0].description = "Pause Minting on the FEI PSM";

        proposal[1].target = MainnetAddresses.PCV_GUARDIAN;
        proposal[1].value = 0;
        proposal[1].arguments = abi.encodeWithSignature(
            "withdrawAllERC20ToSafeAddress(address, address)",
            MainnetAddresses.VOLT_FEI_PSM,
            MainnetAddresses.VOLT
        );
        proposal[1].description = "Remove all VOLT from FEI PSM";

        proposal[2].target = MainnetAddresses.PCV_GUARDIAN;
        proposal[2].value = 0;
        proposal[2].arguments = abi.encodeWithSignature(
            "addWhitelistAddress(address)",
            MainnetAddresses.VOLT_DAI_PSM
        );
        proposal[2]
            .description = "Add DAI PSM to whitelisted addresses on PCV Guardian";
    }

    function mainnetSetup() public override {}

    function mainnetValidate() public override {
        assertEq(
            Volt(MainnetAddresses.VOLT).balanceOf(
                MainnetAddresses.VOLT_FEI_PSM
            ),
            0
        );
        assertTrue(
            PegStabilityModule(MainnetAddresses.VOLT_FEI_PSM).mintPaused()
        );
        assertTrue(
            PCVGuardian(MainnetAddresses.PCV_GUARDIAN).isWhitelistAddress(
                VOLT_DAI_PSM
            )
        );
    }

    /// prevent errors by reverting on arbitrum proposal functions being called on this VIP
    function getArbitrumProposal()
        public
        pure
        override
        returns (TimelockSimulation.action[] memory)
    {
        revert("no arbitrum proposal");
    }

    function arbitrumSetup() public override {
        revert("no arbitrum proposal");
    }

    function arbitrumValidate() public override {
        revert("no arbitrum proposal");
    }
}
