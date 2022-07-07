// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Vm} from "./../unit/utils/Vm.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {getCore, getAddresses} from "./../unit/utils/Fixtures.sol";
import {IVolt, Volt} from "../../volt/Volt.sol";
import {OtcEscrow} from "./../../utils/OtcEscrow.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract IntegrationTestLoanRepayment is DSTest {
    IVolt private volt = IVolt(MainnetAddresses.VOLT);
    IVolt private fei = IVolt(MainnetAddresses.FEI);
    Vm public constant vm = Vm(HEVM_ADDRESS);

    /// @notice amount of fei to pay off loan
    uint256 public constant feiAmount = 10_170_000e18;

    /// @notice amount of volt to receive upon repayment
    uint256 public constant voltAmount = 10_000_000e18;

    /// @notice escrow contract
    OtcEscrow public otcEscrow;

    address public feiDaoTimelock = MainnetAddresses.FEI_DAO_TIMELOCK;
    address public voltTimelock = MainnetAddresses.VOLT_TIMELOCK;

    function setUp() public {
        otcEscrow = new OtcEscrow(
            MainnetAddresses.FEI_DAO_TIMELOCK, /// beneficiary
            MainnetAddresses.VOLT_TIMELOCK, /// recipient
            MainnetAddresses.VOLT, /// received token
            MainnetAddresses.FEI, /// sent token
            voltAmount, /// received amount
            feiAmount /// sent amount
        );

        if (volt.allowance(feiDaoTimelock, address(otcEscrow)) < voltAmount) {
            vm.prank(feiDaoTimelock);
            volt.approve(address(otcEscrow), voltAmount);
        }
        if (fei.balanceOf(address(otcEscrow)) < feiAmount) {
            vm.prank(MainnetAddresses.GOVERNOR);
            fei.transfer(address(otcEscrow), feiAmount);
        }
    }

    function testSetup() public {
        assertEq(
            volt.allowance(feiDaoTimelock, address(otcEscrow)),
            voltAmount
        );
        assertEq(fei.balanceOf(address(otcEscrow)), feiAmount);

        assertEq(otcEscrow.beneficiary(), feiDaoTimelock);
        assertEq(otcEscrow.recipient(), voltTimelock);
        assertEq(otcEscrow.receivedToken(), MainnetAddresses.VOLT);
        assertEq(otcEscrow.sentToken(), MainnetAddresses.FEI);
        assertEq(otcEscrow.sentAmount(), feiAmount);
        assertEq(otcEscrow.receivedAmount(), voltAmount);
    }

    function testSwap() public {
        uint256 startingBalanceOtcEscrowFei = fei.balanceOf(address(otcEscrow));
        uint256 startingBalanceFeiTimelockVolt = volt.balanceOf(feiDaoTimelock);

        vm.prank(feiDaoTimelock);
        otcEscrow.swap();

        uint256 endingBalanceOtcEscrowFei = fei.balanceOf(address(otcEscrow));
        uint256 endingBalanceFeiTimelockVolt = volt.balanceOf(feiDaoTimelock);

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
        uint256 startingBalanceVoltTimeFei = fei.balanceOf(voltTimelock);

        vm.prank(voltTimelock);
        otcEscrow.revoke();

        uint256 endingBalanceOtcEscrowFei = fei.balanceOf(address(otcEscrow));
        uint256 endingBalanceVoltTimeFei = fei.balanceOf(voltTimelock);

        assertEq(
            startingBalanceOtcEscrowFei - endingBalanceOtcEscrowFei,
            feiAmount
        );
        assertEq(endingBalanceOtcEscrowFei, 0);
        assertEq(
            endingBalanceVoltTimeFei - startingBalanceVoltTimeFei,
            feiAmount
        );
    }
}
