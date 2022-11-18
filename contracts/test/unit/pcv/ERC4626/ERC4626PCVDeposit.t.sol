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

    event PCVOracleUpdated(address oldOracle, address newOracle);

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

    /// @notice checks that only PCV Controller role can withdraw
    function testWithdrawOnlyPCVController(uint120 withdrawAmount) public {
        address pcvReceiver = address(100);
        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        tokenizedVaultPCVDeposit.withdraw(pcvReceiver, withdrawAmount);
    }

    /// @notice checks that withdraw works when withdrawing valid amount
    function testWithdrawValidAmount(uint120 withdrawAmount) public {
        utilDepositTokens(withdrawAmount);
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), withdrawAmount);
        address pcvReceiver = address(100);
        vm.prank(addresses.pcvControllerAddress);
        vm.expectEmit(true, false, false, true, address(tokenizedVaultPCVDeposit));
        emit Withdrawal(addresses.pcvControllerAddress, pcvReceiver, withdrawAmount);
        tokenizedVaultPCVDeposit.withdraw(pcvReceiver, withdrawAmount);
        assertEq(token.balanceOf(pcvReceiver), withdrawAmount);
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), 0);
    }

    /// @notice checks that withdraw works when withdrawing valid amount
    function testWithdrawPartialValidAmount(uint120 depositAmount, uint120 withdrawAmount) public {
        vm.assume(depositAmount > withdrawAmount);
        utilDepositTokens(depositAmount);
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), depositAmount);
        address pcvReceiver = address(100);
        vm.prank(addresses.pcvControllerAddress);
        vm.expectEmit(true, false, false, true, address(tokenizedVaultPCVDeposit));
        emit Withdrawal(addresses.pcvControllerAddress, pcvReceiver, withdrawAmount);
        tokenizedVaultPCVDeposit.withdraw(pcvReceiver, withdrawAmount);
        assertEq(token.balanceOf(pcvReceiver), withdrawAmount);
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), depositAmount - withdrawAmount);
    }

    /// @notice checks that if shares are locked, you cannot withdraw full deposit
    /// this test locks the total amount of shares in the vault before trying to withdraw
    function testWithdrawMoreThanAvailable(uint120 withdrawAmount) public {
        vm.assume(withdrawAmount > 0);
        utilDepositTokens(withdrawAmount);
        tokenizedVault.mockLockShares(withdrawAmount, address(tokenizedVaultPCVDeposit));
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), withdrawAmount);
        address pcvReceiver = address(100);
        vm.prank(addresses.pcvControllerAddress);
        vm.expectRevert("ERC4626: withdraw more than max");
        tokenizedVaultPCVDeposit.withdraw(pcvReceiver, withdrawAmount);
    }

    /// @notice checks the function withdrawMax withdraw all tokens if no shares locked
    function testWithdrawMaxWhenNoLock(uint120 withdrawAmount) public {
        vm.assume(withdrawAmount > 0);
        utilDepositTokens(withdrawAmount);
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), withdrawAmount);
        address pcvReceiver = address(100);
        vm.prank(addresses.pcvControllerAddress);
        vm.expectEmit(true, false, false, true, address(tokenizedVaultPCVDeposit));
        emit Withdrawal(addresses.pcvControllerAddress, pcvReceiver, withdrawAmount);
        tokenizedVaultPCVDeposit.withdrawMax(pcvReceiver);
        assertEq(token.balanceOf(pcvReceiver), withdrawAmount);
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), 0);
    }

    /// @notice checks the function withdrawMax withdraw all available tokens 
    /// when some shares are locked in the vault
    function testWithdrawMaxWhenLock(uint120 depositAmount, uint120 lockAmount) public {
        vm.assume(depositAmount > 0);
        vm.assume(lockAmount > 0);
        vm.assume(lockAmount < depositAmount);
        utilDepositTokens(depositAmount);
        tokenizedVault.mockLockShares(lockAmount, address(tokenizedVaultPCVDeposit));
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), depositAmount);
        address pcvReceiver = address(100);
        uint256 withdrawableAmount = depositAmount - lockAmount;
        vm.prank(addresses.pcvControllerAddress);
        vm.expectEmit(true, false, false, true, address(tokenizedVaultPCVDeposit));
        emit Withdrawal(addresses.pcvControllerAddress, pcvReceiver, withdrawableAmount);
        tokenizedVaultPCVDeposit.withdrawMax(pcvReceiver);
        assertEq(token.balanceOf(pcvReceiver), withdrawableAmount);
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), depositAmount - withdrawableAmount);
    }

    /// @notice checks that the oracle can only be set by governor
    function testSetPCVOracleOnlyGovernor() public {
        MockPCVOracle oracle = new MockPCVOracle();
        vm.expectRevert("CoreRef: Caller is not a governor");
        tokenizedVaultPCVDeposit.setPCVOracle(address(oracle));
    }

    /// @notice checks that the PCVOracle can be replaced
    function testSetPCVOracle() public {
        address oldOracle = tokenizedVaultPCVDeposit.pcvOracle();
        MockPCVOracle oracle = new MockPCVOracle();
        vm.prank(addresses.governorAddress);
        vm.expectEmit(true, false, false, true, address(tokenizedVaultPCVDeposit));
        emit PCVOracleUpdated(oldOracle, address(oracle));
        tokenizedVaultPCVDeposit.setPCVOracle(address(oracle));
        assertEq(tokenizedVaultPCVDeposit.pcvOracle(), address(oracle));
    }

    /// @notice checks that the PCVOracle, when replaced, update the lastRecordedBalance
    function testSetPCVOracle(uint120 deposit1, uint120 profit) public {
        vm.assume(deposit1 > 0);
        vm.assume(profit > 0);
        utilDepositTokens(deposit1);
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), deposit1);
        tokenizedVault.mockGainSome(profit);
        // here, after the profit, we do not call accrue() so the lastRecordedBalance does not change
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), deposit1);

        address oldOracle = tokenizedVaultPCVDeposit.pcvOracle();
        MockPCVOracle oracle = new MockPCVOracle();
        vm.prank(addresses.governorAddress);
        vm.expectEmit(true, false, false, true, address(tokenizedVaultPCVDeposit));
        emit PCVOracleUpdated(oldOracle, address(oracle));
        tokenizedVaultPCVDeposit.setPCVOracle(address(oracle));
        assertEq(tokenizedVaultPCVDeposit.pcvOracle(), address(oracle));
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), uint256(deposit1) + uint256(profit));
    }
}
