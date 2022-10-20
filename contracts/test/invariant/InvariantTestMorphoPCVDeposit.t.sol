// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Vm} from "../unit/utils/Vm.sol";
import {ICore} from "../../core/ICore.sol";
import {DSTest} from "../unit/utils/DSTest.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {MockMorpho} from "../../mock/MockMorpho.sol";
import {DSInvariantTest} from "../unit/utils/DSInvariantTest.sol";
import {MorphoCompoundPCVDeposit} from "../../pcv/morpho/MorphoCompoundPCVDeposit.sol";
import {getCore, getAddresses, VoltTestAddresses} from "../unit/utils/Fixtures.sol";

/// @dev Modified from Solmate ERC20 Invariant Test (https://github.com/transmissions11/solmate/blob/main/src/test/ERC20.t.sol)
contract InvariantTestMorphoCompoundPCVDeposit is DSTest, DSInvariantTest {
    MorphoPCVDeposit public invariant;
    ICore public core;
    MorphoCompoundPCVDeposit private morphoDeposit;
    MockMorpho private morpho;
    MockERC20 private token;

    function setUp() public {
        core = getCore();
        token = new MockERC20();
        morpho = new MockMorpho(IERC20(address(token)));
        morphoDeposit = new MorphoCompoundPCVDeposit(
            address(core),
            address(0), /// cToken is not used in mock morpho deposit
            address(token),
            address(morpho),
            address(morpho)
        );
        invariant = new MorphoPCVDeposit(morphoDeposit, token, morpho);

        addTargetContract(address(invariant));
    }

    function invariantDepositedAmount() public {
        assertEq(morphoDeposit.depositedAmount(), invariant.totalDeposited());
        assertEq(morphoDeposit.balance(), invariant.totalDeposited());
    }

    function invariantBalanceOf() public {
        assertEq(morphoDeposit.balance(), morpho.balances(address(invariant)));
        assertEq(morphoDeposit.balance(), token.balanceOf(address(morpho)));
    }
}

contract MorphoPCVDeposit is DSTest {
    VoltTestAddresses public addresses = getAddresses();
    Vm private vm = Vm(HEVM_ADDRESS);
    uint256 public totalDeposited;
    MorphoCompoundPCVDeposit public immutable morphoDeposit;
    MockERC20 private immutable token;
    MockMorpho private immutable morpho;

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
