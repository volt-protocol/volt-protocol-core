pragma solidity =0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {Vm} from "./../../utils/Vm.sol";
import {ICore} from "../../../../core/ICore.sol";
import {DSTest} from "./../../utils/DSTest.sol";
import {stdError} from "../../../unit/utils/StdLib.sol";
import {IPCVDeposit} from "../../../../pcv/IPCVDeposit.sol";
import {MockPCVOracle} from "../../../../mock/MockPCVOracle.sol";
import {MockERC20, IERC20} from "../../../../mock/MockERC20.sol";
import {MockERC4626Vault} from "../../../../mock/MockERC4626Vault.sol";
import {ERC4626PCVDeposit} from "../../../../pcv/ERC4626/ERC4626PCVDeposit.sol";
import {getCore, getAddresses, VoltTestAddresses} from "./../../utils/Fixtures.sol";

contract UnitTestERC4626PCVDeposit is DSTest {
    using SafeCast for *;

    event Deposit(address indexed _from, uint256 _amount);

    event Harvest(address indexed _token, int256 _profit, uint256 _timestamp);

    event Withdrawal(
        address indexed _caller,
        address indexed _to,
        uint256 _amount
    );

    ICore private core;

    ERC4626PCVDeposit private tokenizedVaultPCVDeposit;
    MockERC4626Vault private tokenizedVault;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    VoltTestAddresses public addresses = getAddresses();

    /// @notice token to deposit in the vault
    MockERC20 private token;

    function setUp() public {
        core = getCore();
        token = new MockERC20();
        tokenizedVault = new MockERC4626Vault(MockERC20(address(token)));

        tokenizedVaultPCVDeposit = new ERC4626PCVDeposit(
            address(core),
            address(token),
            address(tokenizedVault)
        );

        vm.label(address(tokenizedVault), "Vault");
        vm.label(address(token), "Token");
    }

    function testSetup() public {
        assertEq(tokenizedVault.asset(), address(token));
        assertEq(tokenizedVaultPCVDeposit.vault(), address(tokenizedVault));
    }

    /// @notice util function to deposit tokens to the vault from the PCV deposit
    function utilDepositTokens(uint256 amountToDeposit) public {
        uint256 vaultPreviousBalanceOfToken = token.balanceOf(address(tokenizedVault));
        token.mint(address(tokenizedVaultPCVDeposit), amountToDeposit);
        tokenizedVaultPCVDeposit.deposit();
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), amountToDeposit);
        assertEq(token.balanceOf(address(tokenizedVault)), vaultPreviousBalanceOfToken + amountToDeposit);
        assertEq(token.balanceOf(address(tokenizedVaultPCVDeposit)), 0);
    }

    /// @notice checks that the PCVDeposit cannot be deployed if there is a 
    /// mismatch between the PCVDeposit token and the vault token
    function testUnderlyingMismatchConstructionFails() public {
        MockERC20 vaultToken = new MockERC20();
        MockERC4626Vault vault = new MockERC4626Vault(MockERC20(address(vaultToken)));

        MockERC20 depositToken = new MockERC20();

        vm.expectRevert("ERC4626PCVDeposit: Underlying mismatch");
        new ERC4626PCVDeposit(
            address(core),
            address(depositToken),
            address(vault)
        );
    }

    /// @notice checks thatwhen using the PCVDeposit deposit function, all tokens should be sent to the vault
    function testDeposit(uint120 depositAmount) public {
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), 0);
        token.mint(address(tokenizedVaultPCVDeposit), depositAmount);
        assertEq(token.balanceOf(address(tokenizedVaultPCVDeposit)), depositAmount);

        tokenizedVaultPCVDeposit.deposit();

        // assert that all tokens have been sent to the vault
        assertEq(token.balanceOf(address(tokenizedVaultPCVDeposit)), 0);
        assertEq(token.balanceOf(address(tokenizedVault)), depositAmount);

        // assert that the last recorded balance variable has been updated
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), depositAmount);
    }

    /// @notice checks that when using the deposit function multiple times, should refresh 'lastRecordedBalance'
    function testDeposits(uint120[4] calldata depositAmount) public {
        uint256 sumDeposit;

        for (uint256 i = 0; i < 4; i++) {
            token.mint(address(tokenizedVaultPCVDeposit), depositAmount[i]);

            if (depositAmount[i] != 0) {
                /// harvest event is not emitted if deposit amount is 0
                vm.expectEmit(true, false, false, true, address(tokenizedVaultPCVDeposit));
                if (tokenizedVaultPCVDeposit.balance() != 0) {
                    emit Harvest(address(token), 0, block.timestamp);
                }
                emit Deposit(address(this), depositAmount[i]);
            }
            tokenizedVaultPCVDeposit.deposit();

            sumDeposit += depositAmount[i];
            assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), sumDeposit);
        }

        assertEq(
            tokenizedVaultPCVDeposit.lastRecordedBalance(),
            tokenizedVault.convertToAssets(tokenizedVault.balanceOf(address(tokenizedVaultPCVDeposit)))
        );
    }

    /// @notice checks that the function accrue, when nothing changes, does not change anything
    function testAccrueWhenNoChangeShouldNotChangeAnything() public {
        utilDepositTokens(10000 * 1e18);
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), 10000 * 1e18);
        tokenizedVaultPCVDeposit.accrue();
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), 10000 * 1e18);
    }
    
    /// @notice checks that if the vault gain profits, then the deposit balance should gain them too
    /// this test assume 0 fees from the vault and that the pcvdeposit is the only participant in the vault
    function testAccrueWhenProfitShouldSaveProfit(uint120 profit) public {
        utilDepositTokens(10000 * 1e18);
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), 10000 * 1e18);
        tokenizedVault.mockGainSome(profit);
        tokenizedVaultPCVDeposit.accrue();
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), uint256(profit) + 10000 * 1e18);
    }
    
    /// @notice checks that if the vault lose profits, then the deposit balance should lose them too
    /// this test assume 0 fees from the vault and that the pcvdeposit is the only participant in the vault
    function testAccrueWhenLossShouldSaveLoss(uint120 lossAmount) public {
        // assume that the vault cannot lose more than 10k tokens
        vm.assume(lossAmount < 10000 * 1e18);
        utilDepositTokens(10000 * 1e18);
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), 10000 * 1e18);
        tokenizedVault.mockLoseSome(lossAmount);
        tokenizedVaultPCVDeposit.accrue();
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), 10000 * 1e18 - uint256(lossAmount));
    }

    /// @notice checks that when no shares locked, the balance is the same as the withdrawable balance
    function testBalanceIsEqualToWithdrawableBalanceWhenNoLock(uint120 amountToDeposit) public {
        utilDepositTokens(amountToDeposit);
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), uint256(amountToDeposit));
        assertEq(tokenizedVaultPCVDeposit.balance(), uint256(amountToDeposit));
        assertEq(tokenizedVaultPCVDeposit.withdrawableBalance(), uint256(amountToDeposit));
    }

    /// @notice checks that when some shares are locked, the balance should not be the same as
    /// the withdrawable balance
    function testBalanceIsNotEqualToWithdrawableBalanceWhenSharesLocked(uint120 amountToDeposit, uint120 amountToLock) public {
        vm.assume(amountToDeposit > amountToLock);
        utilDepositTokens(amountToDeposit);
        tokenizedVault.mockLockShares(amountToLock, address(tokenizedVaultPCVDeposit));
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), uint256(amountToDeposit));
        assertEq(tokenizedVaultPCVDeposit.balance(), uint256(amountToDeposit));
        assertEq(tokenizedVaultPCVDeposit.withdrawableBalance(), uint256(amountToDeposit - amountToLock));
    }






/*
    function testWithdrawAll(uint120[4] calldata depositAmount) public {
        testDeposits(depositAmount);

        uint256 sumDeposit;
        for (uint256 i = 0; i < 4; i++) {
            sumDeposit += depositAmount[i];
        }

        assertEq(token.balanceOf(address(this)), 0);

        vm.prank(addresses.pcvControllerAddress);
        vm.expectEmit(true, true, false, true, address(morphoDeposit));
        emit Withdrawal(
            addresses.pcvControllerAddress,
            address(this),
            sumDeposit
        );
        morphoDeposit.withdrawAll(address(this));

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

        vm.expectEmit(true, false, false, true, address(morphoDeposit));
        emit Harvest(
            address(token),
            uint256(profitAccrued).toInt256(),
            block.timestamp
        );
        uint256 lastRecordedBalance = morphoDeposit.accrue();
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

            vm.prank(addresses.pcvControllerAddress);

            vm.expectEmit(true, true, false, true, address(morphoDeposit));
            emit Withdrawal(
                addresses.pcvControllerAddress,
                to,
                amountToWithdraw
            );

            if (balance != 0 || lastRecordedBalance != 0) {
                emit Harvest(address(token), 0, block.timestamp); /// no profits as already accrued
            }

            morphoDeposit.withdraw(to, amountToWithdraw);

            assertEq(morphoDeposit.lastRecordedBalance(), sumDeposit);
            assertEq(
                morphoDeposit.lastRecordedBalance(),
                morpho.balances(address(morphoDeposit))
            );
        }
    }

    function testSetPCVOracleSucceedsAndHookCalledSuccessfully(
        uint120[4] calldata depositAmount,
        uint248[10] calldata withdrawAmount,
        uint120 profitAccrued,
        address to
    ) public {
        MockPCVOracle oracle = new MockPCVOracle();

        vm.prank(addresses.governorAddress);
        morphoDeposit.setPCVOracle(address(oracle));

        assertEq(morphoDeposit.pcvOracle(), address(oracle));

        vm.assume(to != address(0));
        testWithdraw(depositAmount, withdrawAmount, profitAccrued, to);

        uint256 sumDeposit = uint256(depositAmount[0]) +
            uint256(depositAmount[1]) +
            uint256(depositAmount[2]) +
            uint256(depositAmount[3]) +
            uint256(profitAccrued);

        for (uint256 i = 0; i < 10; i++) {
            if (withdrawAmount[i] > sumDeposit) {
                continue;
            }
            sumDeposit -= withdrawAmount[i];
        }
        morphoDeposit.accrue();

        assertEq(oracle.pcvAmount(), sumDeposit.toInt256());
    }

    function testSetPCVOracleSucceedsAndHookCalledSuccessfullyAfterDeposit(
        uint120[4] calldata depositAmount,
        uint248[10] calldata withdrawAmount,
        uint120 profitAccrued,
        address to
    ) public {
        vm.assume(to != address(0));
        testWithdraw(depositAmount, withdrawAmount, profitAccrued, to);

        uint256 sumDeposit = uint256(depositAmount[0]) +
            uint256(depositAmount[1]) +
            uint256(depositAmount[2]) +
            uint256(depositAmount[3]) +
            uint256(profitAccrued);

        for (uint256 i = 0; i < 10; i++) {
            if (withdrawAmount[i] > sumDeposit) {
                continue;
            }
            sumDeposit -= withdrawAmount[i];
        }

        MockPCVOracle oracle = new MockPCVOracle();
        vm.prank(addresses.governorAddress);
        morphoDeposit.setPCVOracle(address(oracle));
        assertEq(morphoDeposit.pcvOracle(), address(oracle));

        assertEq(oracle.pcvAmount(), sumDeposit.toInt256());
    }

    function testEmergencyActionWithdrawSucceedsGovernor(
        uint120 amount
    ) public {
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
        vm.prank(addresses.pcvControllerAddress);
        vm.expectRevert(stdError.arithmeticError); /// reverts with underflow when trying to withdraw more than balance
        morphoDeposit.withdraw(address(this), 1);
    }

    //// paused

    function testDepositWhenPausedFails() public {
        vm.prank(addresses.governorAddress);
        morphoDeposit.pause();
        vm.expectRevert("Pausable: paused");
        morphoDeposit.deposit();
    }

    function testAccrueWhenPausedFails() public {
        vm.prank(addresses.governorAddress);
        morphoDeposit.pause();
        vm.expectRevert("Pausable: paused");
        morphoDeposit.accrue();
    }

    function testSetPCVOracleSucceedsGovernor() public {
        MockPCVOracle oracle = new MockPCVOracle();
        vm.prank(addresses.governorAddress);
        morphoDeposit.setPCVOracle(address(oracle));
        assertEq(morphoDeposit.pcvOracle(), address(oracle));
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

    function testSetPCVOracleFailsNonGovernor() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        morphoDeposit.setPCVOracle(address(this));
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
        morphoDeposit.withdraw(address(this), 10);
    }

    function testReentrantWithdrawAllFails() public {
        _reentrantSetup();
        vm.prank(addresses.pcvControllerAddress);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        morphoDeposit.withdrawAll(address(this));
    }
    */
}
