// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Vm} from "../unit/utils/Vm.sol";
import {ICore} from "../../core/ICore.sol";
import {DSTest} from "../unit/utils/DSTest.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {MockMorpho} from "../../mock/MockMorpho.sol";
import {MockPCVOracle} from "../../mock/MockPCVOracle.sol";
import {DSInvariantTest} from "../unit/utils/DSInvariantTest.sol";
import {MorphoCompoundPCVDeposit} from "../../pcv/morpho/MorphoCompoundPCVDeposit.sol";
import {getCore, getAddresses, VoltTestAddresses} from "../unit/utils/Fixtures.sol";

/// note all variables have to be public and not immutable otherwise foundry
/// will not run invariant tests

/// @dev Modified from Solmate ERC20 Invariant Test (https://github.com/transmissions11/solmate/blob/main/src/test/ERC20.t.sol)
contract InvariantTestMorphoCompoundPCVDeposit is DSTest, DSInvariantTest {
    using SafeCast for *;

    MorphoPCVDepositTest public morphoTest;
    MockPCVOracle public pcvOracle;
    ICore public core;
    MorphoCompoundPCVDeposit public morphoDeposit;
    MockMorpho public morpho;
    MockERC20 public token;
    Vm private vm = Vm(HEVM_ADDRESS);
    VoltTestAddresses public addresses = getAddresses();

    function setUp() public {
        pcvOracle = new MockPCVOracle();
        core = getCore();
        token = new MockERC20();
        morpho = new MockMorpho(IERC20(address(token)));
        morphoDeposit = new MorphoCompoundPCVDeposit(
            address(core),
            address(morpho),
            address(token),
            address(morpho),
            address(morpho)
        );
        morphoTest = new MorphoPCVDepositTest(morphoDeposit, token, morpho);

        vm.prank(addresses.governorAddress);
        morphoDeposit.setPCVOracle(address(pcvOracle));

        addTargetContract(address(morphoTest));
    }

    function invariantLastRecordedBalance() public {
        assertEq(
            morphoDeposit.lastRecordedBalance(),
            morphoTest.totalDeposited()
        );
        assertEq(morphoDeposit.balance(), morphoTest.totalDeposited());
    }

    function invariantPcvOracle() public {
        assertEq(
            morphoDeposit.lastRecordedBalance(),
            pcvOracle.pcvAmount().toUint256()
        );
        assertEq(morphoDeposit.lastRecordedBalance(), morphoDeposit.balance());
        assertEq(morphoDeposit.balance(), morphoTest.totalDeposited());
    }

    function invariantBalanceOf() public {
        assertEq(
            morphoDeposit.balance(),
            morpho.balances(address(morphoDeposit))
        );
    }
}

contract MorphoPCVDepositTest is DSTest {
    VoltTestAddresses public addresses = getAddresses();
    Vm private vm = Vm(HEVM_ADDRESS);
    uint256 public totalDeposited;
    MorphoCompoundPCVDeposit public morphoDeposit;
    MockERC20 public token;
    MockMorpho public morpho;

    constructor(
        MorphoCompoundPCVDeposit _morphoDeposit,
        MockERC20 _token,
        MockMorpho _morpho
    ) {
        morphoDeposit = _morphoDeposit;
        token = _token;
        morpho = _morpho;
    }

    function increaseBalance(uint256 amount) public {
        token.mint(address(morphoDeposit), amount);
        morphoDeposit.deposit();
        unchecked {
            /// unchecked because token or MockMorpho will revert
            /// from an integer overflow
            totalDeposited += amount;
        }
    }

    function decreaseBalance(uint256 amount) public {
        if (amount > totalDeposited) return;

        vm.prank(addresses.pcvControllerAddress);
        morphoDeposit.withdraw(address(this), amount);
        unchecked {
            /// unchecked because amount is always less than or equal
            /// to totalDeposited
            totalDeposited -= amount;
        }
    }

    function withdrawEntireBalance() public {
        vm.prank(addresses.pcvControllerAddress);
        morphoDeposit.withdrawAll(address(this));
        totalDeposited = 0;
    }

    function increaseBalanceViaInterest(uint256 interestAmount) public {
        token.mint(address(morpho), interestAmount);
        morpho.setBalance(
            address(morphoDeposit),
            totalDeposited + interestAmount
        );
        morphoDeposit.accrue(); /// accrue interest so morpho and pcv deposit are synced
        unchecked {
            /// unchecked because token or MockMorpho will revert
            /// from an integer overflow
            totalDeposited += interestAmount;
        }
    }
}
