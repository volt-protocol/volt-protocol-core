//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {TimelockSimulation} from "../utils/TimelockSimulation.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {ArbitrumAddresses} from "../fixtures/ArbitrumAddresses.sol";
import {DSTest} from "./../../unit/utils/DSTest.sol";
import {Core} from "../../../core/Core.sol";
import {Vm} from "./../../unit/utils/Vm.sol";
import {IVIP} from "./IVIP.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";

contract vip8 is DSTest, IVIP {
    using SafeERC20 for IERC20;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    function getMainnetProposal()
        public
        pure
        override
        returns (TimelockSimulation.action[] memory proposal)
    {
        proposal = new TimelockSimulation.action[](2);

        proposal[0].target = MainnetAddresses.FEI;
        proposal[0].value = 0;
        proposal[0].arguments = abi.encodeWithSignature(
            "approve(address,uint)",
            MainnetAddresses.MAKER_ROUTER,
            type(uint256).max
        );
        proposal[0].description = "Timelock approves router to spend FEI";

        proposal[1].target = MainnetAddresses.FEI;
        proposal[1].value = 0;
        proposal[1].arguments = abi.encodeWithSignature(
            "swapAllFeiForDai(address)",
            MainnetAddresses.VOLT_DAI_PSM
        );
        proposal[1].description = "Swaps FEI for DAI proceeds sent to DAI PSM";
    }

    function mainnetSetup() public override {
        vm.startPrank(MainnetAddresses.GOVERNOR);

        PCVGuardian(MainnetAddresses.PCV_GUARDIAN)
            .withdrawAllERC20ToSafeAddress(
                MainnetAddresses.VOLT_FEI_PSM,
                MainnetAddresses.FEI
            );

        PegStabilityModule(MainnetAddresses.VOLT_FEI_PSM).pauseRedeem();

        uint256 feiBalance = IERC20(MainnetAddresses.FEI).balanceOf(
            MainnetAddresses.GOVERNOR
        );

        IERC20(MainnetAddresses.FEI).safeTransfer(
            MainnetAddresses.TIMELOCK_CONTROLLER,
            feiBalance
        );
    }

    function mainnetValidate() public override {
        assertTrue(
            PegStabilityModule(MainnetAddresses.VOLT_FEI_PSM).redeemPaused()
        );

        assertEq(
            IERC20(MainnetAddresses.FEI).balanceOf(
                MainnetAddresses.VOLT_FEI_PSM
            ),
            0
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
