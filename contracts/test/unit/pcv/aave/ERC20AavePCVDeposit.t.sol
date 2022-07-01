// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Vm} from "./../../utils/Vm.sol";
import {ICore} from "../../../../core/ICore.sol";
import {DSTest} from "./../../utils/DSTest.sol";
import {MockERC20, MockLendingPool} from "../../../../mock/MockLendingPool.sol";
import {ERC20AavePCVDeposit, LendingPool, IncentivesController} from "../../../../pcv/aave/ERC20AavePCVDeposit.sol";
import {getCore, getAddresses, VoltTestAddresses} from "./../../utils/Fixtures.sol";

contract ERC20AavePCVDepositUnitTest is DSTest {
    using SafeCast for *;

    IERC20 private aToken;
    MockERC20 private token;
    MockLendingPool private lendingPool;
    ERC20AavePCVDeposit private aaveDeposit;
    ICore private core;
    VoltTestAddresses public addresses = getAddresses();
    Vm public constant vm = Vm(HEVM_ADDRESS);

    function setUp() public {
        core = getCore();
        lendingPool = new MockLendingPool();
        aToken = lendingPool.aToken();
        token = new MockERC20();
        aaveDeposit = new ERC20AavePCVDeposit(
            address(core),
            LendingPool(address(lendingPool)),
            IERC20(address(token)),
            IERC20(address(aToken)),
            IncentivesController(address(0)) /// incentives controller is not tested in unit tests
        );
    }

    /// only pcv controller successfully withdraws
    function testPCVControllerWithdraws() public {
        uint256 amount = 1000;
        token.mint(address(aaveDeposit), amount);
        aaveDeposit.deposit();

        vm.prank(addresses.pcvControllerAddress);
        aaveDeposit.withdraw(address(this), amount);
    }

    /// non pcv controller cannot withdraw
    function testNonPCVControllerCannotWithdraw() public {
        vm.expectRevert(bytes("CoreRef: Caller is not a PCV controller"));
        aaveDeposit.withdraw(address(this), 1000);
    }
}
