pragma solidity =0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {Vm} from "@forge-std/Vm.sol";
import {Test} from "@forge-std/Test.sol";
import {CoreV2} from "@voltprotocol/core/CoreV2.sol";
import {stdError} from "@forge-std/StdError.sol";
import {MockERC20} from "@test/mock/MockERC20.sol";
import {MockCToken} from "@test/mock/MockCToken.sol";
import {MockMorpho} from "@test/mock/MockMorpho.sol";
import {IPCVDeposit} from "@voltprotocol/pcv/IPCVDeposit.sol";
import {PCVGuardian} from "@voltprotocol/pcv/PCVGuardian.sol";
import {getCoreV2} from "@test/unit/utils/Fixtures.sol";
import {SystemEntry} from "@voltprotocol/entry/SystemEntry.sol";
import {MockERC20, IERC20} from "@test/mock/MockERC20.sol";
import {MorphoCompoundPCVDeposit} from "@voltprotocol/pcv/morpho/MorphoCompoundPCVDeposit.sol";
import {TestAddresses as addresses} from "@test/unit/utils/TestAddresses.sol";
import {MockMorphoMaliciousReentrancy} from "@test/mock/MockMorphoMaliciousReentrancy.sol";
import {IGlobalReentrancyLock, GlobalReentrancyLock} from "@voltprotocol/core/GlobalReentrancyLock.sol";

contract UnitTestMorphoCompoundPCVDeposit is Test {
    using SafeCast for *;

    event Deposit(address indexed _from, uint256 _amount);

    event Harvest(address indexed _token, int256 _profit, uint256 _timestamp);

    event Withdrawal(
        address indexed _caller,
        address indexed _to,
        uint256 _amount
    );

    CoreV2 private core;
    SystemEntry public entry;
    MockMorpho private morpho;
    PCVGuardian private pcvGuardian;
    MorphoCompoundPCVDeposit private morphoDeposit;
    MockMorphoMaliciousReentrancy private maliciousMorpho;

    /// @notice token to deposit
    MockERC20 private token;

    /// @notice global reentrancy lock
    IGlobalReentrancyLock private lock;

    function setUp() public {
        core = getCoreV2();
        token = new MockERC20();
        lock = IGlobalReentrancyLock(
            address(new GlobalReentrancyLock(address(core)))
        );
        entry = new SystemEntry(address(core));
        morpho = new MockMorpho(IERC20(address(token)));
        maliciousMorpho = new MockMorphoMaliciousReentrancy(
            IERC20(address(token))
        );

        morphoDeposit = new MorphoCompoundPCVDeposit(
            address(core),
            address(morpho),
            address(token),
            address(morpho),
            address(morpho)
        );
        address[] memory toWhitelist = new address[](1);
        toWhitelist[0] = address(morphoDeposit);

        pcvGuardian = new PCVGuardian(
            address(core),
            address(this),
            toWhitelist
        );

        vm.startPrank(addresses.governorAddress);
        core.grantLocker(address(entry));
        core.grantLocker(address(pcvGuardian));
        core.grantLocker(address(morphoDeposit));
        core.grantLocker(address(maliciousMorpho));
        core.grantPCVController(address(pcvGuardian));
        core.grantPCVGuard(address(this));
        core.setGlobalReentrancyLock(lock);
        vm.stopPrank();

        vm.label(address(morpho), "Morpho");
        vm.label(address(token), "Token");
        vm.label(address(morphoDeposit), "MorphoDeposit");

        maliciousMorpho.setMorphoCompoundPCVDeposit(address(morphoDeposit));
    }

    function testSetup() public {
        assertEq(morphoDeposit.token(), address(token));
        assertEq(morphoDeposit.lens(), address(morpho));
        assertEq(address(morphoDeposit.morpho()), address(morpho));
        assertEq(morphoDeposit.cToken(), address(morpho));
        assertEq(morphoDeposit.lastRecordedBalance(), 0);
    }

    function testUnderlyingMismatchConstructionFails() public {
        MockCToken cToken = new MockCToken(address(1));

        vm.expectRevert("MorphoCompoundPCVDeposit: Underlying mismatch");
        new MorphoCompoundPCVDeposit(
            address(core),
            address(cToken),
            address(token),
            address(morpho),
            address(morpho)
        );
    }

    function testDeposit(uint120 depositAmount) public {
        assertEq(morphoDeposit.lastRecordedBalance(), 0);
        token.mint(address(morphoDeposit), depositAmount);

        entry.deposit(address(morphoDeposit));

        assertEq(morphoDeposit.lastRecordedBalance(), depositAmount);
    }

    function testDeposits(uint120[4] calldata depositAmount) public {
        uint256 sumDeposit;

        for (uint256 i = 0; i < 4; i++) {
            token.mint(address(morphoDeposit), depositAmount[i]);

            if (depositAmount[i] != 0) {
                /// harvest event is not emitted if deposit amount is 0
                vm.expectEmit(true, false, false, true, address(morphoDeposit));
                if (morphoDeposit.balance() != 0) {
                    emit Harvest(address(token), 0, block.timestamp);
                }
                emit Deposit(address(entry), depositAmount[i]);
            }
            entry.deposit(address(morphoDeposit));

            sumDeposit += depositAmount[i];
            assertEq(morphoDeposit.lastRecordedBalance(), sumDeposit);
        }

        assertEq(
            morphoDeposit.lastRecordedBalance(),
            morpho.balances(address(morphoDeposit))
        );
    }

    function testWithdrawAll(uint120[4] calldata depositAmount) public {
        testDeposits(depositAmount);

        uint256 sumDeposit;
        for (uint256 i = 0; i < 4; i++) {
            sumDeposit += depositAmount[i];
        }

        assertEq(token.balanceOf(address(this)), 0);

        vm.expectEmit(true, true, false, true, address(morphoDeposit));
        emit Withdrawal(address(pcvGuardian), address(this), sumDeposit);
        pcvGuardian.withdrawAllToSafeAddress(address(morphoDeposit));

        assertEq(token.balanceOf(address(this)), sumDeposit);
        assertEq(morphoDeposit.balance(), 0);
        assertEq(morphoDeposit.lastRecordedBalance(), 0);
    }

    function testAccrue(
        uint120[4] calldata depositAmount,
        uint120 profitAccrued
    ) public {
        testDeposits(depositAmount);

        uint256 sumDeposit;
        for (uint256 i = 0; i < 4; i++) {
            sumDeposit += depositAmount[i];
        }
        morpho.setBalance(address(morphoDeposit), sumDeposit + profitAccrued);

        if (
            morphoDeposit.balance() != 0 ||
            morphoDeposit.lastRecordedBalance() != 0
        ) {
            vm.expectEmit(true, false, false, true, address(morphoDeposit));
            emit Harvest(
                address(token),
                uint256(profitAccrued).toInt256(),
                block.timestamp
            );
        }
        uint256 lastRecordedBalance = entry.accrue(address(morphoDeposit));
        assertEq(lastRecordedBalance, sumDeposit + profitAccrued);
        assertEq(lastRecordedBalance, morphoDeposit.lastRecordedBalance());
    }

    function testWithdraw(
        uint120[4] calldata depositAmount,
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

            uint256 balance = morphoDeposit.balance();
            uint256 lastRecordedBalance = morphoDeposit.lastRecordedBalance();

            vm.expectEmit(true, true, false, true, address(morphoDeposit));
            emit Withdrawal(
                address(pcvGuardian),
                address(this),
                amountToWithdraw
            );

            if (balance != 0 || lastRecordedBalance != 0) {
                emit Harvest(address(token), 0, block.timestamp); /// no profits as already accrued
            }

            pcvGuardian.withdrawToSafeAddress(
                address(morphoDeposit),
                amountToWithdraw
            );

            assertEq(morphoDeposit.lastRecordedBalance(), sumDeposit);
            assertEq(
                morphoDeposit.lastRecordedBalance(),
                morpho.balances(address(morphoDeposit))
            );
        }
    }

    function testEmergencyActionWithdrawSucceedsGovernor(
        uint120 amount
    ) public {
        token.mint(address(morphoDeposit), amount);
        entry.deposit(address(morphoDeposit));

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

        assertEq(morphoDeposit.lastRecordedBalance(), amount);
        assertEq(morphoDeposit.balance(), 0);
    }

    function testEmergencyActionSucceedsGovernorDeposit(uint120 amount) public {
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

        assertEq(morphoDeposit.lastRecordedBalance(), 0);
        assertEq(morphoDeposit.balance(), amount);
    }

    function testWithdrawFailsOverAmountHeld() public {
        vm.expectRevert(stdError.arithmeticError); /// reverts with underflow when trying to withdraw more than balance
        pcvGuardian.withdrawToSafeAddress(address(morphoDeposit), 1);
    }

    //// paused

    function testDepositWhenPausedFails() public {
        vm.prank(addresses.governorAddress);
        morphoDeposit.pause();
        vm.expectRevert("Pausable: paused");
        entry.deposit(address(morphoDeposit));
    }

    function testAccrueWhenPausedFails() public {
        vm.prank(addresses.governorAddress);
        morphoDeposit.pause();
        vm.expectRevert("Pausable: paused");
        entry.accrue(address(morphoDeposit));
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
            address(maliciousMorpho), /// cToken is not used in mock morpho deposit
            address(token),
            address(maliciousMorpho),
            address(maliciousMorpho)
        );

        vm.prank(addresses.governorAddress);
        core.grantLocker(address(morphoDeposit));

        maliciousMorpho.setMorphoCompoundPCVDeposit(address(morphoDeposit));
    }

    function testReentrantAccrueFails() public {
        _reentrantSetup();
        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        entry.accrue(address(morphoDeposit));
    }

    function testReentrantDepositFails() public {
        _reentrantSetup();
        token.mint(address(morphoDeposit), 100);
        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        entry.deposit(address(morphoDeposit));
    }

    function testReentrantWithdrawFails() public {
        _reentrantSetup();
        vm.prank(addresses.pcvControllerAddress);
        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        morphoDeposit.withdraw(address(this), 10);
    }

    function testReentrantWithdrawAllFails() public {
        _reentrantSetup();
        vm.prank(addresses.pcvControllerAddress);
        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        morphoDeposit.withdrawAll(address(this));
    }
}
