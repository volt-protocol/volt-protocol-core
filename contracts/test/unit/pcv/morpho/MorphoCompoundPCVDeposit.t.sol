pragma solidity =0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {Vm} from "./../../utils/Vm.sol";
import {ICore} from "../../../../core/ICore.sol";
import {DSTest} from "./../../utils/DSTest.sol";
import {MockERC20} from "../../../../mock/MockERC20.sol";
import {MockMorpho} from "../../../../mock/MockMorpho.sol";
import {TribeRoles} from "../../../../core/TribeRoles.sol";
import {IPCVDeposit} from "../../../../pcv/IPCVDeposit.sol";
import {PCVGuardAdmin} from "../../../../pcv/PCVGuardAdmin.sol";
import {MockERC20, IERC20} from "../../../../mock/MockERC20.sol";
import {MorphoCompoundPCVDeposit} from "../../../../pcv/morpho/MorphoCompoundPCVDeposit.sol";
import {MockMorphoMaliciousReentrancy} from "../../../../mock/MockMorphoMaliciousReentrancy.sol";
import {getCore, getAddresses, VoltTestAddresses} from "./../../utils/Fixtures.sol";

import "hardhat/console.sol";

contract UnitTestMorphoCompoundPCVDeposit is DSTest {
    using SafeCast for *;

    event Harvest(address indexed _token, int256 _profit, uint256 _timestamp);

    event Withdrawal(
        address indexed _caller,
        address indexed _to,
        uint256 _amount
    );

    ICore private core;

    MorphoCompoundPCVDeposit private morphoDeposit;
    MockMorpho private morpho;
    MockMorphoMaliciousReentrancy private maliciousMorpho;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    VoltTestAddresses public addresses = getAddresses();

    /// @notice token to deposit
    MockERC20 private token;

    function setUp() public {
        core = getCore();
        token = new MockERC20();
        morpho = new MockMorpho(IERC20(address(token)));
        maliciousMorpho = new MockMorphoMaliciousReentrancy(
            IERC20(address(token))
        );

        morphoDeposit = new MorphoCompoundPCVDeposit(
            address(core),
            address(0), /// cToken is not used in mock morpho deposit
            address(token),
            address(morpho),
            address(morpho)
        );

        vm.label(address(morpho), "Morpho");
        vm.label(address(token), "Token");
        vm.label(address(morphoDeposit), "MorphoDeposit");

        maliciousMorpho.setMorphoCompoundPCVDeposit(address(morphoDeposit));
    }

    function testSetup() public {
        assertEq(morphoDeposit.token(), address(token));
        assertEq(morphoDeposit.lens(), address(morpho));
        assertEq(address(morphoDeposit.morpho()), address(morpho));
        assertEq(morphoDeposit.cToken(), address(0));
        assertEq(morphoDeposit.depositedAmount(), 0);
    }

    function testDeposit(uint256 depositAmount) public {
        assertEq(morphoDeposit.depositedAmount(), 0);
        token.mint(address(morphoDeposit), depositAmount);

        morphoDeposit.deposit();

        assertEq(morphoDeposit.depositedAmount(), depositAmount);
    }

    function testDeposits(uint248[4] calldata depositAmount) public {
        uint256 sumDeposit;

        for (uint256 i = 0; i < 4; i++) {
            token.mint(address(morphoDeposit), depositAmount[i]);

            if (depositAmount[i] != 0) {
                /// harvest event is not emitted if deposit amount is 0
                vm.expectEmit(true, false, false, true, address(morphoDeposit));
                emit Harvest(address(token), 0, block.timestamp);
            }
            morphoDeposit.deposit();

            sumDeposit += depositAmount[i];
            assertEq(morphoDeposit.depositedAmount(), sumDeposit);
        }

        assertEq(
            morphoDeposit.depositedAmount(),
            morpho.balances(address(morphoDeposit))
        );
    }

    function testWithdrawAll(uint248[4] calldata depositAmount) public {
        testDeposits(depositAmount);

        uint256 sumDeposit;
        for (uint256 i = 0; i < 4; i++) {
            sumDeposit += depositAmount[i];
        }

        assertEq(token.balanceOf(address(this)), 0);

        vm.prank(addresses.pcvControllerAddress);
        morphoDeposit.withdrawAll(address(this));

        assertEq(token.balanceOf(address(this)), sumDeposit);
        assertEq(morphoDeposit.balance(), 0);
        assertEq(morphoDeposit.depositedAmount(), 0);
    }

    function testAccrue(
        uint248[4] calldata depositAmount,
        uint120 profitAccrued
    ) public {
        testDeposits(depositAmount);

        uint256 sumDeposit;
        for (uint256 i = 0; i < 4; i++) {
            sumDeposit += depositAmount[i];
        }
        morpho.setBalance(address(morphoDeposit), sumDeposit + profitAccrued);

        vm.expectEmit(true, false, false, true, address(morphoDeposit));
        emit Harvest(
            address(token),
            uint256(profitAccrued).toInt256(),
            block.timestamp
        );

        assertEq(morphoDeposit.accrue(), sumDeposit + profitAccrued);
    }

    function testWithdraw(
        uint248[4] calldata depositAmount,
        uint248[10] calldata withdrawAmount,
        uint120 profitAccrued,
        address to
    ) public {
        vm.assume(to != address(0));
        testAccrue(depositAmount, profitAccrued);
        token.mint(address(morpho), profitAccrued); /// top up balance so withdraws don't revert

        uint256 sumDeposit = uint256(depositAmount[0]) +
            uint256(depositAmount[1]) +
            uint256(depositAmount[2]) +
            uint256(depositAmount[3]) +
            uint256(profitAccrued);
        for (uint256 i = 0; i < 10; i++) {
            uint256 amountToWithdraw = withdrawAmount[i];
            if (amountToWithdraw > sumDeposit) {
                /// skip if not enough to withdraw
                continue;
            }

            sumDeposit -= amountToWithdraw;

            vm.prank(addresses.pcvControllerAddress);

            /// TODO finalize this later
            // vm.expectEmit(true, true, false, true, address(morphoDeposit));
            // emit Withdrawal(addresses.pcvControllerAddress, to, amountToWithdraw);

            vm.expectEmit(true, false, false, true, address(morphoDeposit));
            emit Harvest(address(token), 0, block.timestamp); /// no profits as already accrued
            morphoDeposit.withdraw(to, amountToWithdraw);

            assertEq(morphoDeposit.depositedAmount(), sumDeposit);
            assertEq(
                morphoDeposit.depositedAmount(),
                morpho.balances(address(morphoDeposit))
            );
        }
    }

    function testEmergencyActionWithdrawSucceedsGovernor(uint256 amount)
        public
    {
        token.mint(address(morphoDeposit), amount);
        morphoDeposit.deposit();

        MorphoCompoundPCVDeposit.Call[]
            memory calls = new MorphoCompoundPCVDeposit.Call[](1);
        calls[0].callData = abi.encodeWithSignature(
            "withdraw(address,uint256)",
            address(this),
            amount
        );
        calls[0].target = address(morpho);

        vm.prank(addresses.governorAddress);
        morphoDeposit.emergencyAction(calls);

        assertEq(morphoDeposit.depositedAmount(), amount);
        assertEq(morphoDeposit.balance(), 0);
    }

    function testEmergencyActionSucceedsGovernorDeposit(uint256 amount) public {
        vm.assume(amount != 0);
        token.mint(address(morphoDeposit), amount);

        MorphoCompoundPCVDeposit.Call[]
            memory calls = new MorphoCompoundPCVDeposit.Call[](2);
        calls[0].callData = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(morphoDeposit.morpho()),
            amount
        );
        calls[0].target = address(token);
        calls[1].callData = abi.encodeWithSignature(
            "supply(address,address,uint256)",
            address(morphoDeposit),
            address(morphoDeposit),
            amount
        );
        calls[1].target = address(morpho);

        vm.prank(addresses.governorAddress);
        morphoDeposit.emergencyAction(calls);

        console.log(
            "morphoDeposit.depositedAmount(): ",
            morphoDeposit.depositedAmount()
        );
        console.log("morphoDeposit.balance(): ", morphoDeposit.balance());
        assertEq(morphoDeposit.depositedAmount(), 0);
        assertEq(morphoDeposit.balance(), amount);
    }

    //// access controls

    function testEmergencyActionFailsNonGovernor() public {
        MorphoCompoundPCVDeposit.Call[]
            memory calls = new MorphoCompoundPCVDeposit.Call[](1);
        calls[0].callData = abi.encodeWithSignature(
            "withdraw(address,uint256)",
            address(this),
            100
        );
        calls[0].target = address(morpho);

        vm.expectRevert("CoreRef: Caller is not a governor");
        morphoDeposit.emergencyAction(calls);
    }

    function testWithdrawFailsNonGovernor() public {
        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        morphoDeposit.withdraw(address(this), 100);
    }

    function testWithdrawAllFailsNonGovernor() public {
        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        morphoDeposit.withdrawAll(address(this));
    }

    //// reentrancy

    function _reentrantSetup() private {
        morphoDeposit = new MorphoCompoundPCVDeposit(
            address(core),
            address(0), /// cToken is not used in mock morpho deposit
            address(token),
            address(maliciousMorpho),
            address(maliciousMorpho)
        );

        maliciousMorpho.setMorphoCompoundPCVDeposit(address(morphoDeposit));
    }

    function testReentrantAccrueFails() public {
        _reentrantSetup();
        vm.expectRevert("ReentrancyGuard: reentrant call");
        morphoDeposit.accrue();
    }

    function testReentrantDepositFails() public {
        _reentrantSetup();
        token.mint(address(morphoDeposit), 100);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        morphoDeposit.deposit();
    }

    function testReentrantWithdrawFails() public {
        _reentrantSetup();
        vm.prank(addresses.pcvControllerAddress);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        morphoDeposit.withdraw(address(this), 0);
    }

    function testReentrantWithdrawAllFails() public {
        _reentrantSetup();
        vm.prank(addresses.pcvControllerAddress);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        morphoDeposit.withdrawAll(address(this));
    }
}