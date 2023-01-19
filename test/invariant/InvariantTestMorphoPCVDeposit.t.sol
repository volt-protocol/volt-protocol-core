// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Vm} from "@forge-std/Vm.sol";
import {CoreV2} from "@voltprotocol/core/CoreV2.sol";
import {Test} from "@forge-std/Test.sol";
import {MockERC20} from "@test/mock/MockERC20.sol";
import {getCoreV2} from "@test/unit/utils/Fixtures.sol";
import {MockMorpho} from "@test/mock/MockMorpho.sol";
import {PCVGuardian} from "@voltprotocol/pcv/PCVGuardian.sol";
import {IPCVOracle} from "@voltprotocol/oracle/IPCVOracle.sol";
import {SystemEntry} from "@voltprotocol/entry/SystemEntry.sol";
import {MockPCVOracle} from "@test/mock/MockPCVOracle.sol";
import {InvariantTest} from "@test/invariant/InvariantTest.sol";
import {MorphoCompoundPCVDeposit} from "@voltprotocol/pcv/morpho/MorphoCompoundPCVDeposit.sol";
import {TestAddresses as addresses} from "@test/unit/utils/TestAddresses.sol";
import {IGlobalReentrancyLock, GlobalReentrancyLock} from "@voltprotocol/core/GlobalReentrancyLock.sol";

/// note all variables have to be public and not immutable otherwise foundry
/// will not run invariant tests

/// @dev Modified from Solmate ERC20 Invariant Test (https://github.com/transmissions11/solmate/blob/main/src/test/ERC20.t.sol)
contract InvariantTestMorphoCompoundPCVDeposit is Test, InvariantTest {
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
    MorphoCompoundPCVDeposit public morphoDeposit;

    function setUp() public {
        core = getCoreV2();
        token = new MockERC20();
        pcvOracle = new MockPCVOracle();
        morpho = new MockMorpho(IERC20(address(token)));
        morphoDeposit = new MorphoCompoundPCVDeposit(
            address(core),
            address(morpho),
            address(token),
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

contract MorphoPCVDepositTest is Test {
    uint256 public totalDeposited;

    MockERC20 public token;
    MockMorpho public morpho;
    SystemEntry public entry;
    PCVGuardian public pcvGuardian;
    MorphoCompoundPCVDeposit public morphoDeposit;

    constructor(
        MorphoCompoundPCVDeposit _morphoDeposit,
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
