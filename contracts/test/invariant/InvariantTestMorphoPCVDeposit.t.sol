// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Vm} from "../unit/utils/Vm.sol";
import {CoreV2} from "../../core/CoreV2.sol";
import {DSTest} from "../unit/utils/DSTest.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {getCoreV2} from "../unit/utils/Fixtures.sol";
import {MockMorpho} from "../../mock/MockMorpho.sol";
import {PCVGuardian} from "../../pcv/PCVGuardian.sol";
import {IPCVOracle} from "../../oracle/IPCVOracle.sol";
import {SystemEntry} from "../../entry/SystemEntry.sol";
import {MockPCVOracle} from "../../mock/MockPCVOracle.sol";
import {DSInvariantTest} from "../unit/utils/DSInvariantTest.sol";
import {MorphoPCVDeposit} from "../../pcv/morpho/MorphoPCVDeposit.sol";
import {TestAddresses as addresses} from "../unit/utils/TestAddresses.sol";
import {IGlobalReentrancyLock, GlobalReentrancyLock} from "../../core/GlobalReentrancyLock.sol";

/// note all variables have to be public and not immutable otherwise foundry
/// will not run invariant tests

/// @dev Modified from Solmate ERC20 Invariant Test (https://github.com/transmissions11/solmate/blob/main/src/test/ERC20.t.sol)
contract InvariantTestMorphoCompoundPCVDeposit is DSTest, DSInvariantTest {
    using SafeCast for *;

    /// TODO add invariant test for profit tracking

    CoreV2 public core;
    MockERC20 public token;
    MockMorpho public morpho;
    SystemEntry public entry;
    PCVGuardian public pcvGuardian;
    MockPCVOracle public pcvOracle;
    IGlobalReentrancyLock private lock;
    MorphoPCVDepositTest public morphoTest;
    MorphoPCVDeposit public morphoDeposit;

    Vm private vm = Vm(HEVM_ADDRESS);

    function setUp() public {
        core = getCoreV2();
        token = new MockERC20();
        pcvOracle = new MockPCVOracle();
        morpho = new MockMorpho(IERC20(address(token)));
        morphoDeposit = new MorphoPCVDeposit(
            address(core),
            address(morpho),
            address(token),
            address(0), /// no need for reward token
            address(morpho),
            address(morpho)
        );
        lock = IGlobalReentrancyLock(
            address(new GlobalReentrancyLock(address(core)))
        );

        address[] memory toWhitelist = new address[](1);
        toWhitelist[0] = address(morphoDeposit);

        pcvGuardian = new PCVGuardian(
            address(core),
            address(this),
            toWhitelist
        );

        entry = new SystemEntry(address(core));
        morphoTest = new MorphoPCVDepositTest(
            morphoDeposit,
            token,
            morpho,
            entry,
            pcvGuardian
        );

        vm.startPrank(addresses.governorAddress);

        core.setPCVOracle(IPCVOracle(address(pcvOracle)));

        core.grantPCVGuard(address(morphoTest));
        core.grantPCVController(address(pcvGuardian));

        core.grantLocker(address(entry));
        core.grantLocker(address(pcvGuardian));
        core.grantLocker(address(morphoDeposit));
        core.setGlobalReentrancyLock(lock);

        vm.stopPrank();

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
    Vm private vm = Vm(HEVM_ADDRESS);

    uint256 public totalDeposited;

    MockERC20 public token;
    MockMorpho public morpho;
    SystemEntry public entry;
    PCVGuardian public pcvGuardian;
    MorphoPCVDeposit public morphoDeposit;

    constructor(
        MorphoPCVDeposit _morphoDeposit,
        MockERC20 _token,
        MockMorpho _morpho,
        SystemEntry _entry,
        PCVGuardian _pcvGuardian
    ) {
        morphoDeposit = _morphoDeposit;
        token = _token;
        morpho = _morpho;
        entry = _entry;
        pcvGuardian = _pcvGuardian;
    }

    function increaseBalance(uint256 amount) public {
        token.mint(address(morphoDeposit), amount);
        entry.deposit(address(morphoDeposit));

        unchecked {
            /// unchecked because token or MockMorpho will revert
            /// from an integer overflow
            totalDeposited += amount;
        }
    }

    function decreaseBalance(uint256 amount) public {
        if (amount > totalDeposited) return;

        pcvGuardian.withdrawToSafeAddress(address(morphoDeposit), amount);
        unchecked {
            /// unchecked because amount is always less than or equal
            /// to totalDeposited
            totalDeposited -= amount;
        }
    }

    function withdrawEntireBalance() public {
        pcvGuardian.withdrawAllToSafeAddress(address(morphoDeposit));
        totalDeposited = 0;
    }

    function increaseBalanceViaInterest(uint256 interestAmount) public {
        token.mint(address(morpho), interestAmount);
        morpho.setBalance(
            address(morphoDeposit),
            totalDeposited + interestAmount
        );
        entry.accrue(address(morphoDeposit)); /// accrue interest so morpho and pcv deposit are synced
        unchecked {
            /// unchecked because token or MockMorpho will revert
            /// from an integer overflow
            totalDeposited += interestAmount;
        }
    }
}
