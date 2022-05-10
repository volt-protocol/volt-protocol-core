// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Vm} from "./../utils/Vm.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {getCore, getAddresses, FeiTestAddresses} from "./../utils/Fixtures.sol";
import {MockERC20} from "../../../mock/MockERC20.sol";
import {FeiSavingsRate, ICore, IERC20} from "../../../fei/FeiSavingsRate.sol";
import {Decimal} from "./../../../external/Decimal.sol";
import {Constants} from "./../../../Constants.sol";

contract FeiSavingsRateTest is DSTest {
    using Decimal for Decimal.D256;

    /// @notice fei savings rate
    FeiSavingsRate private fsr;

    /// @notice reference to Fei
    MockERC20 private fei;

    /// @notice reference to the core contract
    ICore private core;

    address public recipient;

    address public feiHolder;

    /// @notice increase price by 3.09% per month
    uint256 public constant basisPointsPayout = 300;

    /// @notice initial mint amount
    uint256 public immutable initialMintAmount = 10e18;

    uint256 public constant lastRecordedPayout = 10; // starting block timestamp

    Vm public constant vm = Vm(HEVM_ADDRESS);
    FeiTestAddresses public addresses = getAddresses();

    function setUp() public {
        vm.warp(lastRecordedPayout);
        recipient = addresses.beneficiaryAddress1;
        feiHolder = addresses.minterAddress; // minter holds all the fei
        core = getCore();
        fei = new MockERC20();
        fei.mint(feiHolder, initialMintAmount);

        fsr = new FeiSavingsRate(
            recipient,
            feiHolder,
            IERC20(address(fei)),
            core
        );
    }

    function testEarnInterestFailsWithoutTimeElapse() public {
        vm.expectRevert(bytes("Fei Savings Rate: No interest to pay"));
        fsr.earnInterest();
    }

    function testClawbackFailsAsNonGovernor() public {
        vm.expectRevert(bytes("Fei Savings Rate: Not Fei governor"));
        fsr.clawback();
    }

    function testClawbackSucceedsAsGovernor() public {
        vm.prank(addresses.governorAddress);
        fsr.clawback();
    }

    function testClawbackSucceedsAsGovernorAndUnclaimedInterestRemoved()
        public
    {
        uint256 mintAmt = 10_000_000e18;
        fei.mint(address(fsr), mintAmt);

        vm.warp(block.timestamp + 1000);
        vm.prank(addresses.governorAddress);
        fsr.clawback();

        assertEq(fsr.lastFeiAmount(), 0);
        assertEq(fsr.lastRecordedPayout(), block.timestamp);
        assertEq(fei.balanceOf(address(fsr)), 0);
        assertEq(fei.balanceOf(addresses.governorAddress), mintAmt);
    }

    function testLastFeiAmountSetCorrectly() public {
        assertEq(initialMintAmount, fsr.lastFeiAmount());
    }

    function testAccruesInterestCorrectly(uint40 x) public {
        vm.assume(x > lastRecordedPayout); // ensure delta is positive to stop reverts

        vm.warp(x);

        uint256 timeDelta = block.timestamp - lastRecordedPayout;
        uint256 expectedAccruedInterest = (timeDelta *
            initialMintAmount *
            basisPointsPayout) /
            Constants.BASIS_POINTS_GRANULARITY /
            Constants.ONE_YEAR;

        assertEq(expectedAccruedInterest, fsr.getPendingInterest());
    }

    function testAccruesAndEarnsInterestCorrectly(uint40 x, uint200 amt)
        public
    {
        vm.assume(x > lastRecordedPayout); // ensure delta is positive to stop reverts
        vm.assume(amt > 100_000);
        uint256 sum;
        unchecked {
            sum = amt + fei.balanceOf(feiHolder);
        }
        vm.assume(sum > amt); /// ensure no overflow on addition
        vm.assume(sum > fei.balanceOf(feiHolder));

        fei.mint(address(fsr), type(uint248).max); /// give the fsr address the max amt of fei tokens to pay out
        fei.mint(feiHolder, amt);
        vm.warp(block.timestamp + 1);
        fsr.earnInterest(); // sync these new token and block timestamp values
        uint256 currentLastRecordedPayout = fsr.lastRecordedPayout();

        vm.warp(block.timestamp + x);

        uint256 timeDelta = block.timestamp - currentLastRecordedPayout;
        uint256 expectedAccruedInterest = (timeDelta *
            (initialMintAmount + amt) *
            basisPointsPayout) /
            Constants.BASIS_POINTS_GRANULARITY /
            Constants.ONE_YEAR;

        uint256 recipientStartingBalance = fei.balanceOf(recipient);
        assertEq(expectedAccruedInterest, fsr.getPendingInterest());
        fsr.earnInterest();
        uint256 recipientEndingBalance = fei.balanceOf(recipient); /// ensure payout amounts are correct
        assertEq(
            recipientEndingBalance - recipientStartingBalance,
            expectedAccruedInterest
        );
    }
}
