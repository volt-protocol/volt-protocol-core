// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Vm} from "../unit/utils/Vm.sol";
import {CoreV2} from "../../core/CoreV2.sol";
import {DSTest} from "../unit/utils/DSTest.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {MockERC4626Vault} from "../../mock/MockERC4626Vault.sol";
import {PCVGuardian} from "../../pcv/PCVGuardian.sol";
import {SystemEntry} from "../../entry/SystemEntry.sol";
import {MockPCVOracle} from "../../mock/MockPCVOracle.sol";
import {DSInvariantTest} from "../unit/utils/DSInvariantTest.sol";
import {ERC4626PCVDeposit} from "../../pcv/ERC4626/ERC4626PCVDeposit.sol";
import {getCoreV2, getAddresses, VoltTestAddresses} from "../unit/utils/Fixtures.sol";

/// note all variables have to be public and not immutable otherwise foundry
/// will not run invariant tests

/// @dev Modified from Solmate ERC20 Invariant Test (https://github.com/transmissions11/solmate/blob/main/src/test/ERC20.t.sol)
contract InvariantTestERC4626PCVDeposit is DSTest, DSInvariantTest {
    using SafeCast for *;

    CoreV2 public core;
    MockERC20 public token;
    MockERC4626Vault public tokenizedVault;
    SystemEntry public entry;
    PCVGuardian public pcvGuardian;
    MockPCVOracle public pcvOracle;
    ERC4626PCVDepositTest public erc4626PCVDepositTest;
    ERC4626PCVDeposit public tokenizedVaultPCVDeposit;

    Vm private vm = Vm(HEVM_ADDRESS);
    VoltTestAddresses public addresses = getAddresses();

    function setUp() public {
        core = getCoreV2();
        token = new MockERC20();
        pcvOracle = new MockPCVOracle();
        tokenizedVault = new MockERC4626Vault(MockERC20(address(token)));
        tokenizedVaultPCVDeposit = new ERC4626PCVDeposit(
            address(core),
            address(token),
            address(tokenizedVault)
        );

        address[] memory toWhitelist = new address[](1);
        toWhitelist[0] = address(tokenizedVaultPCVDeposit);

        pcvGuardian = new PCVGuardian(
            address(core),
            address(this),
            toWhitelist
        );

        entry = new SystemEntry(address(core));
        erc4626PCVDepositTest = new ERC4626PCVDepositTest(
            tokenizedVaultPCVDeposit,
            token,
            tokenizedVault,
            entry,
            pcvGuardian
        );

        vm.startPrank(addresses.governorAddress);

        tokenizedVaultPCVDeposit.setPCVOracle(address(pcvOracle));

        core.grantPCVGuard(address(erc4626PCVDepositTest));
        core.grantPCVController(address(pcvGuardian));

        core.grantLocker(address(pcvGuardian));
        core.grantLocker(address(tokenizedVaultPCVDeposit));

        vm.stopPrank();

        addTargetContract(address(erc4626PCVDepositTest));
    }

    function invariantLastRecordedBalance() public {
        assertEq(
            tokenizedVaultPCVDeposit.lastRecordedBalance(),
            erc4626PCVDepositTest.totalDeposited()
        );
        assertEq(
            tokenizedVaultPCVDeposit.balance(),
            erc4626PCVDepositTest.totalDeposited()
        );
    }

    function invariantPcvOracle() public {
        assertEq(
            tokenizedVaultPCVDeposit.lastRecordedBalance(),
            pcvOracle.pcvAmount().toUint256()
        );
        assertEq(
            tokenizedVaultPCVDeposit.lastRecordedBalance(),
            tokenizedVaultPCVDeposit.balance()
        );
        assertEq(
            tokenizedVaultPCVDeposit.balance(),
            erc4626PCVDepositTest.totalDeposited()
        );
    }

    function invariantBalanceOf() public {
        assertEq(
            tokenizedVaultPCVDeposit.balance(),
            tokenizedVault.convertToAssets(
                tokenizedVault.balanceOf(address(tokenizedVaultPCVDeposit))
            )
        );
    }
}

contract ERC4626PCVDepositTest is DSTest {
    VoltTestAddresses public addresses = getAddresses();
    Vm private vm = Vm(HEVM_ADDRESS);

    uint256 public totalDeposited;

    MockERC20 public token;
    MockERC4626Vault public tokenizedVault;
    SystemEntry public entry;
    PCVGuardian public pcvGuardian;
    ERC4626PCVDeposit public tokenizedVaultPCVDeposit;

    constructor(
        ERC4626PCVDeposit _erc4626PCVDeposit,
        MockERC20 _token,
        MockERC4626Vault _tokenizedVault,
        SystemEntry _entry,
        PCVGuardian _pcvGuardian
    ) {
        tokenizedVaultPCVDeposit = _erc4626PCVDeposit;
        token = _token;
        tokenizedVault = _tokenizedVault;
        entry = _entry;
        pcvGuardian = _pcvGuardian;
    }

    function increaseBalance(uint256 amount) public {
        token.mint(address(tokenizedVaultPCVDeposit), amount);
        entry.deposit(address(tokenizedVaultPCVDeposit));

        unchecked {
            /// unchecked because token or MocktokenizedVault will revert
            /// from an integer overflow
            totalDeposited += amount;
        }
    }

    function decreaseBalance(uint256 amount) public {
        if (amount > totalDeposited) return;

        pcvGuardian.withdrawToSafeAddress(
            address(tokenizedVaultPCVDeposit),
            amount
        );
        unchecked {
            /// unchecked because amount is always less than or equal
            /// to totalDeposited
            totalDeposited -= amount;
        }
    }

    function withdrawEntireBalance() public {
        pcvGuardian.withdrawAllToSafeAddress(address(tokenizedVaultPCVDeposit));
        totalDeposited = 0;
    }

    function increaseBalanceViaInterest(uint256 interestAmount) public {
        tokenizedVault.mockGainSome(interestAmount);
        entry.accrue(address(tokenizedVaultPCVDeposit)); /// accrue interest so tokenizedVault and pcv deposit are synced
        unchecked {
            /// unchecked because token or MocktokenizedVault will revert
            /// from an integer overflow
            totalDeposited += interestAmount;
        }
    }
}
