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
import {MorphoCompoundPCVDeposit} from "../../pcv/morpho/MorphoCompoundPCVDeposit.sol";

contract IntegrationTestMorphoCompoundPCVDeposit is DSTest {
    using SafeCast for *;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    MorphoCompoundPCVDeposit private daiDeposit;
    MorphoCompoundPCVDeposit private usdcDeposit;

    PCVGuardian private immutable pcvGuardian =
        PCVGuardian(MainnetAddresses.PCV_GUARDIAN);

    Core private core = Core(MainnetAddresses.CORE);
    PegStabilityModule private daiPSM =
        PegStabilityModule(MainnetAddresses.VOLT_DAI_PSM);

    IERC20 private dai = IERC20(MainnetAddresses.DAI);
    IERC20 private usdc = IERC20(MainnetAddresses.USDC);

    uint256 public daiBalance;
    uint256 public usdcBalance;

    uint256 targetDaiBalance = 100_000e18;
    uint256 targetUsdcBalance = 100_000e6;

    function setUp() public {
        daiDeposit = new MorphoCompoundPCVDeposit(
            address(core),
            MainnetAddresses.CDAI
        );
        usdcDeposit = new MorphoCompoundPCVDeposit(
            address(core),
            MainnetAddresses.CUSDC
        );

        vm.startPrank(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        dai.transfer(address(daiDeposit), targetDaiBalance);
        usdc.transfer(address(usdcDeposit), targetUsdcBalance);
        vm.stopPrank();

        usdcDeposit.deposit();
        daiDeposit.deposit();
    }

    function testSetup() public {
        assertEq(address(daiDeposit.core()), address(core));
        assertEq(address(usdcDeposit.core()), address(core));

        assertEq(daiDeposit.balanceReportedIn(), address(dai));
        assertEq(usdcDeposit.balanceReportedIn(), address(usdc));

        assertEq(address(daiDeposit.cToken()), address(MainnetAddresses.CDAI));
        assertEq(
            address(usdcDeposit.cToken()),
            address(MainnetAddresses.CUSDC)
        );

        assertEq(address(daiDeposit.token()), address(MainnetAddresses.DAI));
        assertEq(address(usdcDeposit.token()), address(MainnetAddresses.USDC));

        assertApproxEq(
            daiDeposit.balance().toInt256(),
            targetDaiBalance.toInt256(),
            0
        );
        assertApproxEq(
            usdcDeposit.balance().toInt256(),
            targetUsdcBalance.toInt256(),
            0
        );
    }

    function testWithdraw() public {
        vm.startPrank(MainnetAddresses.GOVERNOR);
        usdcDeposit.withdraw(address(this), usdcDeposit.balance());
        daiDeposit.withdraw(address(this), daiDeposit.balance());
        vm.stopPrank();

        assertApproxEq(
            dai.balanceOf(address(this)).toInt256(),
            targetDaiBalance.toInt256(),
            0
        );
        assertApproxEq(
            usdc.balanceOf(address(this)).toInt256(),
            targetUsdcBalance.toInt256(),
            0
        );
    }

    function testDepositNoFundsSucceeds() public {
        usdcDeposit.deposit();
        daiDeposit.deposit();
    }

    function testWithdrawNonGovFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        usdcDeposit.withdraw(address(this), targetUsdcBalance);

        vm.expectRevert("CoreRef: Caller is not a governor");
        daiDeposit.withdraw(address(this), targetDaiBalance);
    }
}
