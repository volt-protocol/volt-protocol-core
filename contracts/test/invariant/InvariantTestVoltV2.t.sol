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

    function invariantBalanceOf() public {
        address[] memory allUsers = new address[](balanceSum.allUserLength());
        uint256 totalBalances;

        for (uint256 i = 0; i < balanceSum.allUserLength(); i++) {
            allUsers[i] = balanceSum.allUsers(i);
            assertEq(
                volt.balanceOf(allUsers[i]),
                balanceSum.balances(balanceSum.allUsers(i))
            );
            assertEq(
                volt.getVotes(allUsers[i]),
                balanceSum.votingPower(allUsers[i])
            );
        }

        for (uint256 i = 0; i < balanceSum.allUserLength(); i++) {
            totalBalances += volt.balanceOf(allUsers[i]);
        }

        uint256 balanceSumTotalBalances = balanceSum
            .recordedTotalSupplyByBalanceOf();

        assertEq(totalBalances, volt.totalSupply());
        assertEq(totalBalances, balanceSumTotalBalances);
    }

    function invariantTotalSupply() public {
        assertTrue(volt.totalSupply() <= type(uint224).max);
    }
}

contract BalanceSum is DSTest {
    VoltV2 volt;
    VoltTestAddresses public addresses = getAddresses();
    Vm private vm = Vm(HEVM_ADDRESS);
    mapping(address => uint256) public balances;
    mapping(address => bool) public isUser;
    mapping(address => uint256) public votingPower;
    address[] public allUsers;
    uint256 public sum;

    constructor(VoltV2 _volt) {
        volt = _volt;
    }

    function recordedTotalSupplyByBalanceOf()
        public
        view
        returns (uint256 totalSupply)
    {
        for (uint256 i = 0; i < allUsers.length; i++) {
            totalSupply += volt.balanceOf(allUsers[i]);
        }
    }

    function mint(address to, uint256 amount) public {
        vm.prank(addresses.governorAddress);
        volt.mint(to, amount);
        unchecked {
            sum += amount;
            checkpointUser(to);
            balances[to] += amount;
        }
    }

    function burnFrom(address from, uint256 amount) public {
        volt.burnFrom(from, amount);
        unchecked {
            sum -= amount;
            checkpointUser(from);
            balances[from] -= amount;
        }
    }

    function burn(uint256 amount) public {
        volt.burn(amount);
        unchecked {
            sum -= amount;
        }
    }

    function approve(address to, uint256 amount) public {
        volt.approve(to, amount);
        checkpointUser(to);
    }

    function transferFrom(address from, address to, uint256 amount) public {
        volt.transferFrom(from, to, amount);

        checkpointUser(to);
        checkpointUser(from);

        unchecked {
            balances[from] -= amount;
            balances[to] += amount;
        }
    }

    function transfer(address to, uint256 amount) public {
        volt.transfer(to, amount);

        checkpointUser(to);
        unchecked {
            balances[to] += amount;
        }
    }

    function allUserLength() public returns (uint256) {
        return allUsers.length;
    }

    function checkpointUser(address user) internal {
        if (isUser[user] == false) {
            allUsers.push(user);
            isUser[user] = true;
        }
        vm.prank(user);
        volt.delegate(user);
        votingPower[user] = volt.getVotes(user);
    }
}
