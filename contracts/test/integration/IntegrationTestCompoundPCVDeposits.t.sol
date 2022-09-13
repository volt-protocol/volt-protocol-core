//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "../unit/utils/Vm.sol";
import {Core} from "../../core/Core.sol";
import {IVolt} from "../../volt/IVolt.sol";
import {DSTest} from "../unit/utils/DSTest.sol";
import {IDSSPSM} from "../../pcv/maker/IDSSPSM.sol";
import {Constants} from "../../Constants.sol";
import {PCVGuardian} from "../../pcv/PCVGuardian.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {PegStabilityModule} from "../../peg/PegStabilityModule.sol";
import {ERC20CompoundPCVDeposit} from "../../pcv/compound/ERC20CompoundPCVDeposit.sol";

contract IntegrationTestCompoundPCVDeposits is DSTest {
    using SafeCast for *;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    ERC20CompoundPCVDeposit private daiDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_DAI_PCV_DEPOSIT);
    ERC20CompoundPCVDeposit private feiDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_FEI_PCV_DEPOSIT);
    ERC20CompoundPCVDeposit private usdcDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT);

    PCVGuardian private immutable pcvGuardian =
        PCVGuardian(MainnetAddresses.PCV_GUARDIAN);

    Core private core = Core(MainnetAddresses.CORE);
    PegStabilityModule private daiPSM =
        PegStabilityModule(MainnetAddresses.VOLT_DAI_PSM);

    IERC20 private dai = IERC20(MainnetAddresses.DAI);
    IVolt private fei = IVolt(MainnetAddresses.FEI);
    IERC20 private usdc = IERC20(MainnetAddresses.USDC);

    uint256 public daiBalance;
    uint256 public usdcBalance;

    function setUp() public {
        daiBalance = daiDeposit.balance();

        vm.prank(MainnetAddresses.CUSDC);
        usdc.transfer(address(usdcDeposit), usdcBalance);
        usdcDeposit.deposit();

        usdcBalance = usdcDeposit.balance();
    }

    function testSetup() public {
        assertEq(address(daiDeposit.core()), address(core));
        assertEq(address(feiDeposit.core()), address(core));
        assertEq(address(usdcDeposit.core()), address(core));

        assertEq(address(daiDeposit.cToken()), address(MainnetAddresses.CDAI));
        assertEq(address(feiDeposit.cToken()), address(MainnetAddresses.CFEI));
        assertEq(
            address(usdcDeposit.cToken()),
            address(MainnetAddresses.CUSDC)
        );

        assertEq(address(daiDeposit.token()), address(MainnetAddresses.DAI));
        assertEq(address(feiDeposit.token()), address(MainnetAddresses.FEI));
        assertEq(address(usdcDeposit.token()), address(MainnetAddresses.USDC));
    }

    function testGuardianAction() public {
        uint256 startingDaiBalance = dai.balanceOf(MainnetAddresses.GOVERNOR);
        uint256 startingFeiBalance = fei.balanceOf(MainnetAddresses.GOVERNOR);
        uint256 startingUsdcBalance = usdc.balanceOf(MainnetAddresses.GOVERNOR);

        uint256 feiToWithdraw = fei.balanceOf(MainnetAddresses.CFEI);

        vm.startPrank(MainnetAddresses.EOA_1);

        pcvGuardian.withdrawAllToSafeAddress(address(daiDeposit));
        pcvGuardian.withdrawToSafeAddress(address(feiDeposit), feiToWithdraw);
        pcvGuardian.withdrawAllToSafeAddress(address(usdcDeposit));

        vm.stopPrank();

        assertApproxEq(
            (dai.balanceOf(MainnetAddresses.GOVERNOR) - startingDaiBalance)
                .toInt256(),
            daiBalance.toInt256(),
            0
        );
        assertApproxEq(
            (fei.balanceOf(MainnetAddresses.GOVERNOR) - startingFeiBalance)
                .toInt256(),
            feiToWithdraw.toInt256(),
            0
        );
        assertApproxEq(
            (usdc.balanceOf(MainnetAddresses.GOVERNOR) - startingUsdcBalance)
                .toInt256(),
            usdcBalance.toInt256(),
            0
        );

        assertTrue(daiDeposit.balance().toInt256() <= 1e20); /// only dust remains, lte 100 dai
        assertTrue(usdcDeposit.balance().toInt256() <= 1e3); /// only dust remains, lte .001 usdc
    }
}
