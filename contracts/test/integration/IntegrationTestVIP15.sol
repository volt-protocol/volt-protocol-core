// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {vip15} from "./vip/vip15.sol";
import {ICore} from "../../core/ICore.sol";
import {IVolt} from "../../volt/Volt.sol";
import {IPCVDeposit} from "../../pcv/IPCVDeposit.sol";
import {IPCVGuardian} from "../../pcv/IPCVGuardian.sol";
import {PriceBoundPSM} from "../../peg/PriceBoundPSM.sol";
import {ERC20Allocator} from "../../pcv/utils/ERC20Allocator.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {TimelockSimulation} from "./utils/TimelockSimulation.sol";

contract IntegrationTestVIP15 is TimelockSimulation, vip15 {
    using SafeCast for *;

    IPCVGuardian private immutable mainnetPCVGuardian =
        IPCVGuardian(MainnetAddresses.PCV_GUARDIAN);

    ERC20Allocator private immutable allocator =
        ERC20Allocator(MainnetAddresses.ERC20ALLOCATOR);
    PriceBoundPSM private immutable usdcPsm =
        PriceBoundPSM(MainnetAddresses.VOLT_USDC_PSM);
    PriceBoundPSM private immutable daiPsm =
        PriceBoundPSM(MainnetAddresses.VOLT_DAI_PSM);

    uint256 startingPrice;
    uint256 endingPrice;

    function setUp() public {
        startingPrice = opt.getCurrentOraclePrice();

        mainnetSetup();
        simulate(
            getMainnetProposal(),
            TimelockController(payable(MainnetAddresses.TIMELOCK_CONTROLLER)),
            mainnetPCVGuardian,
            MainnetAddresses.GOVERNOR,
            MainnetAddresses.EOA_1,
            vm,
            false
        );
        mainnetValidate();

        endingPrice = opt.getCurrentOraclePrice();

        vm.label(address(pcvGuardian), "PCV Guardian");
    }

    function testPriceStaysWithinOneBasisPointAfterUpgrade() public {
        assertApproxEq(int256(startingPrice), int256(endingPrice), 0);
    }

    function testSkimFailsPaused() public {
        vm.expectRevert("Pausable: paused");
        allocator.skim(MainnetAddresses.MORPHO_COMPOUND_DAI_PCV_DEPOSIT);
    }

    function testDripFailsPaused() public {
        vm.expectRevert("Pausable: paused");
        allocator.drip(MainnetAddresses.MORPHO_COMPOUND_DAI_PCV_DEPOSIT);
    }

    function testDoActionFailsPaused() public {
        vm.expectRevert("Pausable: paused");
        allocator.doAction(MainnetAddresses.MORPHO_COMPOUND_DAI_PCV_DEPOSIT);
    }

    function testMintFailsPausedDai() public {
        vm.expectRevert("PegStabilityModule: Minting paused");
        daiPsm.mint(address(0), 0, 0);
    }

    function testMintFailsPausedUsdc() public {
        vm.expectRevert("PegStabilityModule: Minting paused");
        usdcPsm.mint(address(0), 0, 0);
    }
}
