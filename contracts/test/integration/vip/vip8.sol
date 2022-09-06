//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITimelockSimulation} from "../utils/ITimelockSimulation.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {ArbitrumAddresses} from "../fixtures/ArbitrumAddresses.sol";
import {DSTest} from "./../../unit/utils/DSTest.sol";
import {Core} from "../../../core/Core.sol";
import {Vm} from "./../../unit/utils/Vm.sol";
import {IVIP} from "./IVIP.sol";
import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";

contract vip8 is DSTest, IVIP {
    using SafeERC20 for IERC20;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    uint256 public startingFeiBalance;

    function getMainnetProposal()
        public
        pure
        override
        returns (ITimelockSimulation.action[] memory proposal)
    {
        proposal = new ITimelockSimulation.action[](4);

        proposal[0].target = MainnetAddresses.VOLT_FEI_PSM;
        proposal[0].value = 0;
        proposal[0].arguments = abi.encodeWithSignature("pauseRedeem()");
        proposal[0].description = "Pause redemptions on the FEI PSM";

        proposal[1].target = MainnetAddresses.FEI;
        proposal[1].value = 0;
        proposal[1].arguments = abi.encodeWithSignature(
            "approve(address,uint256)",
            MainnetAddresses.MAKER_ROUTER,
            2_400_000e18
        );
        proposal[1].description = "Timelock approves router to spend FEI";

        proposal[2].target = MainnetAddresses.MAKER_ROUTER;
        proposal[2].value = 0;
        proposal[2].arguments = abi.encodeWithSignature(
            "swapAllFeiForDai(address)",
            MainnetAddresses.VOLT_DAI_PSM
        );
        proposal[2].description = "Swaps FEI for DAI proceeds sent to DAI PSM";

        proposal[3].target = MainnetAddresses.FEI;
        proposal[3].value = 0;
        proposal[3].arguments = abi.encodeWithSignature(
            "approve(address,uint256)",
            MainnetAddresses.MAKER_ROUTER,
            0
        );
        proposal[3]
            .description = "Timelock revokes router approval to spend FEI";
    }

    function mainnetSetup() public override {
        vm.startPrank(MainnetAddresses.GOVERNOR);

        PCVGuardian(MainnetAddresses.PCV_GUARDIAN).addWhitelistAddress(
            MainnetAddresses.MAKER_ROUTER
        );

        PCVGuardian(MainnetAddresses.PCV_GUARDIAN)
            .withdrawAllERC20ToSafeAddress(
                MainnetAddresses.VOLT_FEI_PSM,
                MainnetAddresses.FEI
            );

        startingFeiBalance = IERC20(MainnetAddresses.FEI).balanceOf(
            MainnetAddresses.GOVERNOR
        );

        IERC20(MainnetAddresses.FEI).safeTransfer(
            MainnetAddresses.TIMELOCK_CONTROLLER,
            startingFeiBalance
        );

        IERC20(MainnetAddresses.VOLT).safeTransfer(
            MainnetAddresses.VOLT_DAI_PSM,
            2_700_000e18
        );
        vm.stopPrank();
    }

    function mainnetValidate() public override {
        uint256 daiBalance = PegStabilityModule(MainnetAddresses.FEI_DAI_PSM)
            .getRedeemAmountOut(startingFeiBalance);

        assertTrue(
            PegStabilityModule(MainnetAddresses.VOLT_FEI_PSM).redeemPaused()
        );

        assertEq(
            IERC20(MainnetAddresses.DAI).balanceOf(
                MainnetAddresses.VOLT_DAI_PSM
            ),
            daiBalance
        );

        assertEq(
            IERC20(MainnetAddresses.FEI).balanceOf(
                MainnetAddresses.VOLT_FEI_PSM
            ),
            0
        );

        assertEq(
            IERC20(MainnetAddresses.FEI).allowance(
                MainnetAddresses.TIMELOCK_CONTROLLER,
                MainnetAddresses.MAKER_ROUTER
            ),
            0
        );

        assertEq(
            IERC20(MainnetAddresses.VOLT).balanceOf(
                MainnetAddresses.VOLT_DAI_PSM
            ),
            2_700_000e18
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
}
