pragma solidity =0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {Vm} from "./../../utils/Vm.sol";
import {CoreV2} from "../../../../core/CoreV2.sol";
import {DSTest} from "./../../utils/DSTest.sol";
import {stdError} from "../../../unit/utils/StdLib.sol";
import {IPCVDeposit} from "../../../../pcv/IPCVDeposit.sol";
import {MockPCVOracle} from "../../../../mock/MockPCVOracle.sol";
import {SystemEntry} from "../../../../entry/SystemEntry.sol";
import {PCVGuardian} from "../../../../pcv/PCVGuardian.sol";
import {MockERC20, IERC20} from "../../../../mock/MockERC20.sol";
import {MockERC4626Vault} from "../../../../mock/MockERC4626Vault.sol";
import {ERC4626PCVDeposit} from "../../../../pcv/ERC4626/ERC4626PCVDeposit.sol";
import {getCoreV2, getAddresses, VoltTestAddresses} from "./../../utils/Fixtures.sol";
import "../../../../mock/MockERC4626VaultMaliciousReentrancy.sol";

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

    address public safeAddress = address(1000);
    CoreV2 private core;
    SystemEntry public entry;

    ERC4626PCVDeposit private tokenizedVaultPCVDeposit;
    MockERC4626Vault private tokenizedVault;
    PCVGuardian private pcvGuardian;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    VoltTestAddresses public addresses = getAddresses();

    /// @notice token to deposit in the vault
    MockERC20 private token;

    MockERC4626VaultMaliciousReentrancy private maliciousVault;

    function setUp() public {
        core = getCoreV2();
        token = new MockERC20();
        entry = new SystemEntry(address(core));
        tokenizedVault = new MockERC4626Vault(MockERC20(address(token)));
        maliciousVault = new MockERC4626VaultMaliciousReentrancy(
            MockERC20(address(token))
        );

        tokenizedVaultPCVDeposit = new ERC4626PCVDeposit(
            address(core),
            address(token),
            address(tokenizedVault)
        );

        address[] memory toWhitelist = new address[](1);
        toWhitelist[0] = address(tokenizedVaultPCVDeposit);
        pcvGuardian = new PCVGuardian(address(core), safeAddress, toWhitelist);

        vm.startPrank(addresses.governorAddress);
        core.grantLocker(address(entry));
        core.grantLocker(address(pcvGuardian));
        core.grantLocker(address(tokenizedVaultPCVDeposit));
        core.grantPCVController(address(pcvGuardian));
        // core.grantLocker(address(maliciousVault));
        core.grantPCVGuard(address(this));
        vm.stopPrank();

        vm.label(address(tokenizedVault), "Vault");
        vm.label(address(token), "Token");

        maliciousVault.setERC4626PCVDeposit(address(tokenizedVaultPCVDeposit));
    }

    function testSetup() public {
        assertEq(tokenizedVault.asset(), address(token));
        assertEq(tokenizedVaultPCVDeposit.vault(), address(tokenizedVault));
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), 0);
    }

    /// @notice utility function to deposit tokens to the vault from the PCV deposit
    function utilDepositTokens(uint256 amountToDeposit) public {
        uint256 vaultPreviousBalanceOfToken = token.balanceOf(
            address(tokenizedVault)
        );
        token.mint(address(tokenizedVaultPCVDeposit), amountToDeposit);
        entry.deposit(address(tokenizedVaultPCVDeposit));
        assertEq(
            tokenizedVaultPCVDeposit.lastRecordedBalance(),
            amountToDeposit
        );
        assertEq(
            token.balanceOf(address(tokenizedVault)),
            vaultPreviousBalanceOfToken + amountToDeposit
        );
        assertEq(token.balanceOf(address(tokenizedVaultPCVDeposit)), 0);
    }

    /// @notice utility function that simulate another user which deposit to the vault
    /// (not using the PCV Deposit obviously)
    function utilDepositTokensFromAnotherUser(uint256 amountToDeposit) public {
        // make deposit from another user
        address vaultUser = address(101);
        token.mint(vaultUser, amountToDeposit);
        vm.prank(vaultUser);
        token.approve(address(tokenizedVault), amountToDeposit);
        vm.prank(vaultUser);
        tokenizedVault.deposit(amountToDeposit, vaultUser);
    }

    /// @notice checks that the PCVDeposit cannot be deployed if there is a
    /// mismatch between the PCVDeposit token and the vault token
    function testUnderlyingMismatchConstructionFails() public {
        MockERC20 vaultToken = new MockERC20();
        MockERC4626Vault vault = new MockERC4626Vault(
            MockERC20(address(vaultToken))
        );

        MockERC20 depositToken = new MockERC20();

        vm.expectRevert("ERC4626PCVDeposit: Underlying mismatch");
        new ERC4626PCVDeposit(
            address(core),
            address(depositToken),
            address(vault)
        );
    }

    /// @notice checks that when using the PCVDeposit deposit function, all tokens should be sent to the vault
    function testDeposit(uint120 depositAmount) public {
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), 0);
        token.mint(address(tokenizedVaultPCVDeposit), depositAmount);
        assertEq(
            token.balanceOf(address(tokenizedVaultPCVDeposit)),
            depositAmount
        );

        entry.deposit(address(tokenizedVaultPCVDeposit));

        // assert that all tokens have been sent to the vault
        assertEq(token.balanceOf(address(tokenizedVaultPCVDeposit)), 0);
        assertEq(token.balanceOf(address(tokenizedVault)), depositAmount);

        // assert that the last recorded balance variable has been updated
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), depositAmount);
    }

    /// @notice checks that deposit also works when the PCVDeposit is not the only user in the vault
    /// this checks that the accounting in the PCV Deposit is done right
    function testDepositWhenNotAlone(
        uint120 otherUserAmount,
        uint120 depositAmount
    ) public {
        utilDepositTokensFromAnotherUser(otherUserAmount);
        assertEq(token.balanceOf(address(tokenizedVault)), otherUserAmount);

        // make deposit from the PCV Deposit
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), 0);
        token.mint(address(tokenizedVaultPCVDeposit), depositAmount);
        assertEq(
            token.balanceOf(address(tokenizedVaultPCVDeposit)),
            depositAmount
        );

        entry.deposit(address(tokenizedVaultPCVDeposit));

        // assert that all tokens have been sent to the vault
        assertEq(token.balanceOf(address(tokenizedVaultPCVDeposit)), 0);
        assertEq(
            token.balanceOf(address(tokenizedVault)),
            uint256(depositAmount) + uint256(otherUserAmount)
        );

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
                vm.expectEmit(
                    true,
                    false,
                    false,
                    true,
                    address(tokenizedVaultPCVDeposit)
                );
                if (tokenizedVaultPCVDeposit.balance() != 0) {
                    emit Harvest(address(token), 0, block.timestamp);
                }
                emit Deposit(address(entry), depositAmount[i]);
            }
            entry.deposit(address(tokenizedVaultPCVDeposit));

            sumDeposit += depositAmount[i];
            assertEq(
                tokenizedVaultPCVDeposit.lastRecordedBalance(),
                sumDeposit
            );
        }

        assertEq(
            tokenizedVaultPCVDeposit.lastRecordedBalance(),
            tokenizedVault.convertToAssets(
                tokenizedVault.balanceOf(address(tokenizedVaultPCVDeposit))
            )
        );
    }

    /// @notice checks that the function accrue, when nothing changes, does not change anything
    function testAccrueWhenNoChangeShouldNotChangeAnything() public {
        utilDepositTokens(10000 * 1e18);
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), 10000 * 1e18);
        entry.accrue(address(tokenizedVaultPCVDeposit));
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), 10000 * 1e18);
    }

    /// @notice checks that if the vault gain profits, then the deposit balance should gain them too
    /// this test assume 0 fees from the vault and that the pcvdeposit is the only participant in the vault
    function testAccrueWhenProfitShouldSaveProfit(uint120 profit) public {
        utilDepositTokens(10000 * 1e18);
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), 10000 * 1e18);
        tokenizedVault.mockGainSome(profit);
        entry.accrue(address(tokenizedVaultPCVDeposit));
        assertEq(
            tokenizedVaultPCVDeposit.lastRecordedBalance(),
            uint256(profit) + 10000 * 1e18
        );
    }

    /// @notice same as "testAccrueWhenProfitShouldSaveProfit" but add another user to the vault
    /// to check that the accounting is done right and the share are shared between vault users
    function testAccrueWhenProfitWithOtherUserShouldShareProfit(
        uint120 profitAmount
    ) public {
        utilDepositTokensFromAnotherUser(10000 * 1e18);
        utilDepositTokens(10000 * 1e18);
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), 10000 * 1e18);
        tokenizedVault.mockGainSome(profitAmount);
        entry.accrue(address(tokenizedVaultPCVDeposit));
        assertApproxEq(
            tokenizedVaultPCVDeposit.lastRecordedBalance().toInt256(),
            (uint256(10000 * 1e18) + uint256(profitAmount / 2)).toInt256(),
            0
        );
    }

    /// @notice checks that if the vault lose profits, then the deposit balance should lose them too
    /// this test assume 0 fees from the vault and that the pcvdeposit is the only participant in the vault
    function testAccrueWhenLossShouldSaveLoss(uint120 lossAmount) public {
        // assume that the vault cannot lose more than 10k tokens
        vm.assume(lossAmount < 10000 * 1e18);
        utilDepositTokens(10000 * 1e18);
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), 10000 * 1e18);
        tokenizedVault.mockLoseSome(lossAmount);
        entry.accrue(address(tokenizedVaultPCVDeposit));
        assertEq(
            tokenizedVaultPCVDeposit.lastRecordedBalance(),
            10000 * 1e18 - uint256(lossAmount)
        );
    }

    /// @notice same as "testAccrueWhenLossShouldSaveLoss" but add another user to the vault
    /// to check that the accounting is done right and the loss are shared between vault users
    function testAccrueWhenLossWithOtherUserShouldShareLoss(uint120 lossAmount)
        public
    {
        // assume that the vault cannot lose more than the two deposited values
        vm.assume(lossAmount < 20000 * 1e18);
        utilDepositTokensFromAnotherUser(10000 * 1e18);
        utilDepositTokens(10000 * 1e18);
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), 10000 * 1e18);
        tokenizedVault.mockLoseSome(lossAmount);
        entry.accrue(address(tokenizedVaultPCVDeposit));
        assertApproxEq(
            tokenizedVaultPCVDeposit.lastRecordedBalance().toInt256(),
            (uint256(10000 * 1e18) - uint256(lossAmount / 2)).toInt256(),
            10
        );
    }

    /// @notice checks that when no shares locked, the balance is the same as the withdrawable balance
    function testBalanceIsEqualToWithdrawableBalanceWhenNoLock(
        uint120 amountToDeposit
    ) public {
        utilDepositTokens(amountToDeposit);
        assertEq(
            tokenizedVaultPCVDeposit.lastRecordedBalance(),
            uint256(amountToDeposit)
        );
        assertEq(tokenizedVaultPCVDeposit.balance(), uint256(amountToDeposit));
        assertEq(
            tokenizedVaultPCVDeposit.withdrawableBalance(),
            uint256(amountToDeposit)
        );
    }

    /// @notice checks that when some shares are locked, the balance should not be the same as
    /// the withdrawable balance
    function testBalanceIsNotEqualToWithdrawableBalanceWhenSharesLocked(
        uint120 amountToDeposit,
        uint120 amountToLock
    ) public {
        vm.assume(amountToDeposit > amountToLock);
        utilDepositTokens(amountToDeposit);
        tokenizedVault.mockLockShares(
            amountToLock,
            address(tokenizedVaultPCVDeposit)
        );
        assertEq(
            tokenizedVaultPCVDeposit.lastRecordedBalance(),
            uint256(amountToDeposit)
        );
        assertEq(tokenizedVaultPCVDeposit.balance(), uint256(amountToDeposit));
        assertEq(
            tokenizedVaultPCVDeposit.withdrawableBalance(),
            uint256(amountToDeposit - amountToLock)
        );
    }

    /// @notice checks that the withdraw function cannot be used if called is not PCV Controller
    function testCannotWithdrawIfNotPCVController(uint120 withdrawAmount)
        public
    {
        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        tokenizedVaultPCVDeposit.withdraw(address(45), withdrawAmount);
    }

    /// @notice checks that the withdraw function cannot be called directly
    /// even by a pcv controller
    function testCannotWithdrawDirectly(uint120 withdrawAmount) public {
        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        vm.prank(addresses.pcvControllerAddress);
        tokenizedVaultPCVDeposit.withdraw(address(45), withdrawAmount);
    }

    /// @notice checks that the deposit function cannot be called directly
    function testCannotDepositDirectly() public {
        vm.expectRevert("GlobalReentrancyLock: invalid lock level");
        tokenizedVaultPCVDeposit.deposit();
    }

    /// @notice checks that only authorized can withdraw
    function testWithdrawOnlyForAuthorized(uint120 withdrawAmount) public {
        vm.expectRevert("UNAUTHORIZED");
        address randomAddress = address(45);
        vm.prank(randomAddress);
        pcvGuardian.withdrawToSafeAddress(
            address(tokenizedVaultPCVDeposit),
            withdrawAmount
        );
    }

    /// @notice checks that withdraw works when withdrawing valid amount
    function testWithdrawValidAmount(uint120 withdrawAmount) public {
        utilDepositTokens(withdrawAmount);
        assertEq(
            tokenizedVaultPCVDeposit.lastRecordedBalance(),
            withdrawAmount
        );
        vm.expectEmit(
            true,
            false,
            false,
            true,
            address(tokenizedVaultPCVDeposit)
        );
        emit Withdrawal(address(pcvGuardian), safeAddress, withdrawAmount);

        pcvGuardian.withdrawToSafeAddress(
            address(tokenizedVaultPCVDeposit),
            withdrawAmount
        );
        assertEq(token.balanceOf(safeAddress), withdrawAmount);
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), 0);
    }

    /// @notice checks that withdraw works when withdrawing valid amount
    function testWithdrawPartialValidAmount(
        uint120 depositAmount,
        uint120 withdrawAmount
    ) public {
        vm.assume(depositAmount > withdrawAmount);
        utilDepositTokens(depositAmount);
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), depositAmount);
        vm.expectEmit(
            true,
            false,
            false,
            true,
            address(tokenizedVaultPCVDeposit)
        );

        emit Withdrawal(address(pcvGuardian), safeAddress, withdrawAmount);

        pcvGuardian.withdrawToSafeAddress(
            address(tokenizedVaultPCVDeposit),
            withdrawAmount
        );

        assertEq(token.balanceOf(safeAddress), withdrawAmount);
        assertEq(
            tokenizedVaultPCVDeposit.lastRecordedBalance(),
            depositAmount - withdrawAmount
        );
    }

    /// @notice checks that if shares are locked, you cannot withdraw full deposit
    /// this test locks the total amount of shares in the vault before trying to withdraw
    function testWithdrawMoreThanAvailable(uint120 withdrawAmount) public {
        vm.assume(withdrawAmount > 0);
        utilDepositTokens(withdrawAmount);
        tokenizedVault.mockLockShares(
            withdrawAmount,
            address(tokenizedVaultPCVDeposit)
        );
        assertEq(
            tokenizedVaultPCVDeposit.lastRecordedBalance(),
            withdrawAmount
        );
        vm.expectRevert("ERC4626: withdraw more than max");
        pcvGuardian.withdrawToSafeAddress(
            address(tokenizedVaultPCVDeposit),
            withdrawAmount
        );
    }

    /// @notice checks the function withdrawMax withdraw all tokens if no shares locked
    function testWithdrawMaxWhenNoLock(uint120 withdrawAmount) public {
        vm.assume(withdrawAmount > 0);
        utilDepositTokens(withdrawAmount);
        assertEq(
            tokenizedVaultPCVDeposit.lastRecordedBalance(),
            withdrawAmount
        );
        address pcvReceiver = address(100);

        // lock level 1 directly to be able to call withdrawMax function
        // could be removed when/if the pcvGuardian implements withdrawMax function one day
        vm.prank(addresses.governorAddress);
        core.grantLocker(address(this));
        core.lock(1);

        vm.prank(addresses.pcvControllerAddress);
        vm.expectEmit(
            true,
            false,
            false,
            true,
            address(tokenizedVaultPCVDeposit)
        );
        emit Withdrawal(
            addresses.pcvControllerAddress,
            pcvReceiver,
            withdrawAmount
        );
        tokenizedVaultPCVDeposit.withdrawMax(pcvReceiver);
        assertEq(token.balanceOf(pcvReceiver), withdrawAmount);
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), 0);
    }

    /// @notice checks the function withdrawMax withdraw all tokens if no shares locked
    function testWithdrawMaxWhenProfit(
        uint120 withdrawAmount,
        uint120 profitAmount
    ) public {
        vm.assume(withdrawAmount > 0);
        utilDepositTokens(withdrawAmount);
        tokenizedVault.mockGainSome(profitAmount);
        assertEq(
            tokenizedVaultPCVDeposit.lastRecordedBalance(),
            withdrawAmount
        );
        address pcvReceiver = address(100);

        // lock level 1 directly to be able to call withdrawMax function
        // could be removed when/if the pcvGuardian implements withdrawMax function one day
        vm.prank(addresses.governorAddress);
        core.grantLocker(address(this));
        core.lock(1);
        vm.prank(addresses.pcvControllerAddress);
        vm.expectEmit(
            true,
            false,
            false,
            true,
            address(tokenizedVaultPCVDeposit)
        );
        emit Withdrawal(
            addresses.pcvControllerAddress,
            pcvReceiver,
            uint256(withdrawAmount) + uint256(profitAmount)
        );
        tokenizedVaultPCVDeposit.withdrawMax(pcvReceiver);
        assertEq(
            token.balanceOf(pcvReceiver),
            uint256(withdrawAmount) + uint256(profitAmount)
        );
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), 0);
    }

    /// @notice checks the function withdrawMax withdraw all tokens if no shares locked
    function testWithdrawMaxWhenLoss(uint120 withdrawAmount, uint120 lossAmount)
        public
    {
        vm.assume(withdrawAmount > 0);
        vm.assume(lossAmount < withdrawAmount);
        utilDepositTokens(withdrawAmount);
        tokenizedVault.mockLoseSome(lossAmount);
        assertEq(
            tokenizedVaultPCVDeposit.lastRecordedBalance(),
            withdrawAmount
        );
        address pcvReceiver = address(100);
        // lock level 1 directly to be able to call withdrawMax function
        // could be removed when/if the pcvGuardian implements withdrawMax function one day
        vm.prank(addresses.governorAddress);
        core.grantLocker(address(this));
        core.lock(1);

        vm.prank(addresses.pcvControllerAddress);
        vm.expectEmit(
            true,
            false,
            false,
            true,
            address(tokenizedVaultPCVDeposit)
        );
        emit Withdrawal(
            addresses.pcvControllerAddress,
            pcvReceiver,
            uint256(withdrawAmount) - uint256(lossAmount)
        );
        tokenizedVaultPCVDeposit.withdrawMax(pcvReceiver);
        assertEq(
            token.balanceOf(pcvReceiver),
            uint256(withdrawAmount) - uint256(lossAmount)
        );
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), 0);
    }

    /// @notice checks the function withdrawMax withdraw all available tokens
    /// when some shares are locked in the vault
    function testWithdrawMaxWhenLock(uint120 depositAmount, uint120 lockAmount)
        public
    {
        vm.assume(depositAmount > 0);
        vm.assume(lockAmount > 0);
        vm.assume(lockAmount < depositAmount);
        utilDepositTokens(depositAmount);
        tokenizedVault.mockLockShares(
            lockAmount,
            address(tokenizedVaultPCVDeposit)
        );
        assertEq(tokenizedVaultPCVDeposit.lastRecordedBalance(), depositAmount);
        address pcvReceiver = address(100);
        uint256 withdrawableAmount = depositAmount - lockAmount;

        // lock level 1 directly to be able to call withdrawMax function
        // could be removed when/if the pcvGuardian implements withdrawMax function one day
        vm.prank(addresses.governorAddress);
        core.grantLocker(address(this));
        core.lock(1);

        vm.prank(addresses.pcvControllerAddress);
        vm.expectEmit(
            true,
            false,
            false,
            true,
            address(tokenizedVaultPCVDeposit)
        );
        emit Withdrawal(
            addresses.pcvControllerAddress,
            pcvReceiver,
            withdrawableAmount
        );
        tokenizedVaultPCVDeposit.withdrawMax(pcvReceiver);
        assertEq(token.balanceOf(pcvReceiver), withdrawableAmount);
        assertEq(
            tokenizedVaultPCVDeposit.lastRecordedBalance(),
            depositAmount - withdrawableAmount
        );
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
        vm.expectEmit(
            true,
            false,
            false,
            true,
            address(tokenizedVaultPCVDeposit)
        );
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
        vm.expectEmit(
            true,
            false,
            false,
            true,
            address(tokenizedVaultPCVDeposit)
        );
        emit PCVOracleUpdated(oldOracle, address(oracle));
        tokenizedVaultPCVDeposit.setPCVOracle(address(oracle));
        assertEq(tokenizedVaultPCVDeposit.pcvOracle(), address(oracle));
        assertEq(
            tokenizedVaultPCVDeposit.lastRecordedBalance(),
            uint256(deposit1) + uint256(profit)
        );
    }
}
