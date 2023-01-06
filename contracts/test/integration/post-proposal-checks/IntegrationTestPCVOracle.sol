// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {PostProposalCheck} from "./PostProposalCheck.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CoreV2} from "../../../core/CoreV2.sol";
import {VoltV2} from "../../../volt/VoltV2.sol";
import {PCVOracle} from "../../../oracle/PCVOracle.sol";
import {IPCVOracle} from "../../../oracle/IPCVOracle.sol";
import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";

contract IntegrationTestPCVOracle is PostProposalCheck {
    CoreV2 private core;
    IERC20 private dai;
    VoltV2 private volt;
    address private grlm;
    address private morphoDaiPCVDeposit;
    PegStabilityModule private daipsm;
    PCVOracle private pcvOracle;
    PCVGuardian private pcvGuardian;

    function setUp() public override {
        super.setUp();

        core = CoreV2(addresses.mainnet("CORE"));
        dai = IERC20(addresses.mainnet("DAI"));
        volt = VoltV2(addresses.mainnet("VOLT"));
        grlm = addresses.mainnet("GLOBAL_RATE_LIMITED_MINTER");
        morphoDaiPCVDeposit = addresses.mainnet("PCV_DEPOSIT_MORPHO_DAI");
        daipsm = PegStabilityModule(addresses.mainnet("PSM_DAI"));
        pcvOracle = PCVOracle(addresses.mainnet("PCV_ORACLE"));
        pcvGuardian = PCVGuardian(addresses.mainnet("PCV_GUARDIAN"));
    }

    // check that we can read the pcv and it does not revert
    function testReadPcv() public {
        (uint256 liquidPcv, uint256 illiquidPcv, uint256 totalPcv) = pcvOracle
            .getTotalPcv();
        assertTrue(liquidPcv > 0, "Zero liquid PCV");
        assertTrue(illiquidPcv == 0, "Illiquid PCV");
        assertTrue(totalPcv > 0, "Zero PCV");
    }

    // check that we can unset the PCVOracle in Core
    // and that it doesn't break PCV movements (only disables accounting).
    function testUnsetPcvOracle() public {
        address multisig = addresses.mainnet("GOVERNOR");

        vm.prank(multisig);
        core.setPCVOracle(IPCVOracle(address(0)));

        vm.prank(multisig);
        pcvGuardian.withdrawToSafeAddress(morphoDaiPCVDeposit, 100e18);

        // No revert & PCV moved
        assertEq(dai.balanceOf(pcvGuardian.safeAddress()), 100e18);

        // User redeems
        vm.prank(grlm);
        volt.mint(address(this), 100e18);
        volt.approve(address(daipsm), 100e18);
        daipsm.redeem(address(this), 100e18, 104e18);
        assertGt(dai.balanceOf(address(this)), 104e18);
    }
}
