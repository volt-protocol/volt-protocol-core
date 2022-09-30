//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "../unit/utils/Vm.sol";
import {Core} from "../../core/Core.sol";
import {IVolt} from "../../volt/IVolt.sol";
import {IPool} from "../../pcv/maple/IPool.sol";
import {DSTest} from "../unit/utils/DSTest.sol";
import {IDSSPSM} from "../../pcv/maker/IDSSPSM.sol";
import {Constants} from "../../Constants.sol";
import {EulerPCVDeposit} from "../../pcv/euler/EulerPCVDeposit.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";

contract IntegrationTestEulerPCVDeposit is DSTest {
    using SafeCast for *;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    EulerPCVDeposit private usdcDeposit;

    Core private core = Core(MainnetAddresses.CORE);

    IERC20 private usdc = IERC20(MainnetAddresses.USDC);

    uint256 public constant targetUsdcBalance = 100_000e6;

    function setUp() public {
        usdcDeposit = new EulerPCVDeposit(
            address(core),
            MainnetAddresses.EUSDC,
            MainnetAddresses.EULER_MAIN
        );

        vm.prank(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        usdc.transfer(address(usdcDeposit), targetUsdcBalance);

        usdcDeposit.deposit();
    }

    function testSetup() public {
        assertEq(address(usdcDeposit.core()), address(core));
        assertEq(usdcDeposit.balanceReportedIn(), address(usdc));
        assertEq(usdcDeposit.eulerMain(), MainnetAddresses.EULER_MAIN);
        assertEq(address(usdcDeposit.token()), address(MainnetAddresses.USDC));
        assertApproxEq(
            usdcDeposit.balance().toInt256(),
            targetUsdcBalance.toInt256(),
            0
        );
    }

    function testWithdraw() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.withdraw(address(this), targetUsdcBalance - 1); /// balance rounds down, so subtract 1 and things work just fine

        assertEq(usdcDeposit.balance(), 0);
        assertApproxEq(
            usdc.balanceOf(address(this)).toInt256(),
            targetUsdcBalance.toInt256(),
            0
        );
    }

    function testWithdrawAll() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.withdrawAll(address(this));

        assertEq(usdcDeposit.balance(), 0);
        assertApproxEq(
            usdc.balanceOf(address(this)).toInt256(),
            targetUsdcBalance.toInt256(),
            0
        );
    }

    function testWithdrawNonPCVControllerFails() public {
        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        usdcDeposit.withdraw(address(this), targetUsdcBalance);
    }

    function testDepositFailsWhenPaused() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        usdcDeposit.pause();
        assertTrue(usdcDeposit.paused());

        vm.expectRevert("Pausable: paused");
        usdcDeposit.deposit();
    }

    function testWithdrawAllNonPCVControllerFails() public {
        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        usdcDeposit.withdrawAll(address(this));
    }
}
