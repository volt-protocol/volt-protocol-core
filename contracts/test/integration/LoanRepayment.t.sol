// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Vm} from "./../unit/utils/Vm.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {getCore, getAddresses} from "./../unit/utils/Fixtures.sol";
import {IVolt, Volt} from "../../volt/Volt.sol";
import {OtcEscrow} from "./../../utils/OtcEscrow.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IFeiPCVGuardian} from "../../pcv/IFeiPCVGuardian.sol";

contract IntegrationTestLoanRepayment is DSTest {
    IVolt private volt = IVolt(MainnetAddresses.VOLT);
    IVolt private fei = IVolt(MainnetAddresses.FEI);
    Vm public constant vm = Vm(HEVM_ADDRESS);

    /// @notice amount of fei to pay off loan
    uint256 public constant feiAmount = 10_170_000e18;

    /// @notice amount of volt to receive upon repayment
    uint256 public constant voltAmount = 10_000_000e18;

    /// @notice escrow contract
    OtcEscrow public otcEscrow = OtcEscrow(MainnetAddresses.OTC_LOAN_REPAYMENT);

    address public feiTcTimelock = MainnetAddresses.FEI_TC_TIMELOCK;
    address public voltTimelock = MainnetAddresses.VOLT_TIMELOCK;

    IFeiPCVGuardian private pcvGuardian =
        IFeiPCVGuardian(MainnetAddresses.FEI_PCV_GUARDIAN);

    function setUp() public {
        if (volt.allowance(feiTcTimelock, address(otcEscrow)) < voltAmount) {
            vm.prank(feiTcTimelock);
            volt.approve(address(otcEscrow), voltAmount);
        }
        if (!pcvGuardian.isSafeAddress(feiTcTimelock)) {
            vm.prank(feiTcTimelock);
            pcvGuardian.setSafeAddress(feiTcTimelock);
        }
        if (volt.balanceOf(feiTcTimelock) < voltAmount) {
            vm.prank(feiTcTimelock);
            pcvGuardian.withdrawToSafeAddress(
                MainnetAddresses.VOLT_DEPOSIT,
                feiTcTimelock,
                voltAmount,
                false,
                false
            );
        }
        if (fei.balanceOf(address(otcEscrow)) < feiAmount) {
            vm.prank(MainnetAddresses.GOVERNOR);
            fei.transfer(address(otcEscrow), feiAmount);
        }
    }

    function testSetup() public {
        assertEq(volt.allowance(feiTcTimelock, address(otcEscrow)), voltAmount);
        assertEq(fei.balanceOf(address(otcEscrow)), feiAmount);

        assertEq(otcEscrow.beneficiary(), feiTcTimelock);
        assertEq(otcEscrow.recipient(), voltTimelock);
        assertEq(otcEscrow.receivedToken(), MainnetAddresses.VOLT);
        assertEq(otcEscrow.sentToken(), MainnetAddresses.FEI);
        assertEq(otcEscrow.sentAmount(), feiAmount);
        assertEq(otcEscrow.receivedAmount(), voltAmount);
    }

    function testSwap() public {
        uint256 startingBalanceOtcEscrowFei = fei.balanceOf(address(otcEscrow));
        uint256 startingBalanceFeiTimelockVolt = volt.balanceOf(feiTcTimelock);

        vm.prank(feiTcTimelock);
        otcEscrow.swap();

        uint256 endingBalanceOtcEscrowFei = fei.balanceOf(address(otcEscrow));
        uint256 endingBalanceFeiTimelockVolt = volt.balanceOf(feiTcTimelock);

        assertEq(
            startingBalanceFeiTimelockVolt - endingBalanceFeiTimelockVolt,
            voltAmount
        );
        assertEq(endingBalanceFeiTimelockVolt, 0);
        assertEq(
            startingBalanceOtcEscrowFei - endingBalanceOtcEscrowFei,
            feiAmount
        );
    }

    function testRecipientRevokes() public {
        uint256 startingBalanceOtcEscrowFei = fei.balanceOf(address(otcEscrow));
        uint256 startingBalanceVoltTimelockFei = fei.balanceOf(voltTimelock);

        vm.prank(voltTimelock);
        otcEscrow.revoke();

        uint256 endingBalanceOtcEscrowFei = fei.balanceOf(address(otcEscrow));
        uint256 endingBalanceVoltTimelockFei = fei.balanceOf(voltTimelock);

        assertEq(
            startingBalanceOtcEscrowFei - endingBalanceOtcEscrowFei,
            feiAmount
        );
        assertEq(endingBalanceOtcEscrowFei, 0);
        assertEq(
            endingBalanceVoltTimelockFei - startingBalanceVoltTimelockFei,
            feiAmount
        );
    }
}
