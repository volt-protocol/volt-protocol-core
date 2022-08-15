// SPDX-License-Identifier: GPL-3.0-or-later
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
import {PriceBoundPSM} from "../../../peg/PriceBoundPSM.sol";
import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";
import {MakerRouter} from "../../../pcv/maker/MakerRouter.sol";
import {IPCVGuardian} from "../../../pcv/IPCVGuardian.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract vip7 is DSTest, IVIP, AllRoles {
    using SafeERC20 for IERC20;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    function getMainnetProposal()
        public
        pure
        override
        returns (TimelockSimulation.action[] memory proposal)
    {
        proposal = new TimelockSimulation.action[](4);

        proposal[0].target = MainnetAddresses.VOLT_FEI_PSM;
        proposal[0].value = 0;
        proposal[0].arguments = abi.encodeWithSignature("pauseMint()");
        proposal[0].description = "Pause Minting on the FEI PSM";

        proposal[1].target = MainnetAddresses.PCV_GUARDIAN;
        proposal[1].value = 0;
        proposal[1].arguments = abi.encodeWithSignature(
            "withdrawAllERC20ToSafeAddress(address,address)",
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

        proposal[3].target = MainnetAddresses.VOLT_USDC_PSM;
        proposal[3].value = 0;
        proposal[3].arguments = abi.encodeWithSignature("unpauseRedeem()");
        proposal[3].description = "Unpause redemptions for USDC PSM";
    }

    function mainnetSetup() public override {
        vm.startPrank(MainnetAddresses.GOVERNOR);
        IPCVGuardian(MainnetAddresses.PCV_GUARDIAN)
            .withdrawAllERC20ToSafeAddress(
                MainnetAddresses.VOLT_FEI_PSM,
                MainnetAddresses.VOLT
            );

        uint256 balance = IERC20(MainnetAddresses.VOLT).balanceOf(
            MainnetAddresses.GOVERNOR
        );

        IERC20(MainnetAddresses.VOLT).safeTransfer(
            MainnetAddresses.VOLT_DAI_PSM,
            balance
        );
        vm.stopPrank();
    }

    function mainnetValidate() public override {
        assertEq(
            Volt(MainnetAddresses.VOLT).balanceOf(
                MainnetAddresses.VOLT_FEI_PSM
            ),
            0
        );
        assertTrue(PriceBoundPSM(MainnetAddresses.VOLT_FEI_PSM).mintPaused());
        assertTrue(
            PCVGuardian(MainnetAddresses.PCV_GUARDIAN).isWhitelistAddress(
                MainnetAddresses.VOLT_DAI_PSM
            )
        );
        assertTrue(
            !PriceBoundPSM(MainnetAddresses.VOLT_USDC_PSM).redeemPaused()
        );

        assertTrue(PriceBoundPSM(MainnetAddresses.VOLT_DAI_PSM).doInvert());
        assertTrue(PriceBoundPSM(MainnetAddresses.VOLT_DAI_PSM).isPriceValid());
        assertEq(PriceBoundPSM(MainnetAddresses.VOLT_DAI_PSM).floor(), 9_000);
        assertEq(
            PriceBoundPSM(MainnetAddresses.VOLT_DAI_PSM).ceiling(),
            10_000
        );
        assertEq(
            address(PriceBoundPSM(MainnetAddresses.VOLT_DAI_PSM).oracle()),
            MainnetAddresses.ORACLE_PASS_THROUGH
        );
        assertEq(
            address(
                PriceBoundPSM(MainnetAddresses.VOLT_DAI_PSM).backupOracle()
            ),
            address(0)
        );
        assertEq(
            PriceBoundPSM(MainnetAddresses.VOLT_DAI_PSM).decimalsNormalizer(),
            0
        );
        assertEq(
            PriceBoundPSM(MainnetAddresses.VOLT_DAI_PSM).mintFeeBasisPoints(),
            0
        );
        assertEq(
            PriceBoundPSM(MainnetAddresses.VOLT_DAI_PSM).redeemFeeBasisPoints(),
            0
        );
        assertEq(
            address(
                PriceBoundPSM(MainnetAddresses.VOLT_DAI_PSM).underlyingToken()
            ),
            address(MainnetAddresses.DAI)
        );
        assertEq(
            PriceBoundPSM(MainnetAddresses.VOLT_DAI_PSM).reservesThreshold(),
            type(uint256).max
        );
        assertEq(
            address(
                PriceBoundPSM(MainnetAddresses.VOLT_DAI_PSM).surplusTarget()
            ),
            address(1)
        );

        assertEq(
            address(MakerRouter(MainnetAddresses.MAKER_ROUTER).dai()),
            MainnetAddresses.DAI
        );
        assertEq(
            address(MakerRouter(MainnetAddresses.MAKER_ROUTER).fei()),
            MainnetAddresses.FEI
        );
        assertEq(
            address(MakerRouter(MainnetAddresses.MAKER_ROUTER).daiPSM()),
            MainnetAddresses.MAKER_DAI_USDC_PSM
        );
        assertEq(
            address(MakerRouter(MainnetAddresses.MAKER_ROUTER).feiPSM()),
            MainnetAddresses.FEI_DAI_PSM
        );
        assertEq(
            address(MakerRouter(MainnetAddresses.MAKER_ROUTER).core()),
            MainnetAddresses.CORE
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

    function arbitrumSetup() public pure override {
        revert("no arbitrum proposal");
    }

    function arbitrumValidate() public pure override {
        revert("no arbitrum proposal");
    }
}
