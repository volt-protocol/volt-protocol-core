// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {DSTest} from "../unit/utils/DSTest.sol";
import {DSInvariantTest} from "../unit/utils/DSInvariantTest.sol";
import {Vm} from "../unit/utils/Vm.sol";
import {ICore} from "../../core/ICore.sol";
import {getCore, getAddresses, VoltTestAddresses} from "../unit/utils/Fixtures.sol";
import {VoltV2} from "../../volt/VoltV2.sol";

/// @dev Modified from Solmate ERC20 Invariant Test (https://github.com/transmissions11/solmate/blob/main/src/test/ERC20.t.sol)
contract InvariantTestVoltV2 is DSTest, DSInvariantTest {
    BalanceSum public balanceSum;
    VoltV2 public volt;
    ICore public core;

    function setUp() public {
        core = getCore();
        volt = new VoltV2(address(core));
        balanceSum = new BalanceSum(volt);

        addTargetContract(address(balanceSum));
    }

    function invariantBalanceSum() public {
        assertEq(volt.totalSupply(), balanceSum.sum());
    }
}

contract BalanceSum is DSTest {
    VoltV2 volt;
    VoltTestAddresses public addresses = getAddresses();
    Vm private vm = Vm(HEVM_ADDRESS);

    uint256 public sum;

    constructor(VoltV2 _volt) {
        volt = _volt;
    }

    function mint(address to, uint256 amount) public {
        vm.prank(addresses.governorAddress);
        volt.mint(to, amount);
        sum += amount;
    }

    function burnFrom(address from, uint256 amount) public {
        volt.burnFrom(from, amount);
        sum -= amount;
    }

    function burn(uint256 amount) public {
        volt.burn(amount);
        sum -= amount;
    }

    function approve(address to, uint256 amount) public {
        volt.approve(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public {
        volt.transferFrom(from, to, amount);
    }

    function transfer(address to, uint256 amount) public {
        volt.transfer(to, amount);
    }
}
