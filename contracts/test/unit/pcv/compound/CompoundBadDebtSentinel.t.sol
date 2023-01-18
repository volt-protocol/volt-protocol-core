pragma solidity =0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {Vm} from "./../../utils/Vm.sol";
import {Test} from "../../../../../forge-std/src/Test.sol";
import {CoreV2} from "../../../../core/CoreV2.sol";
import {stdError} from "../../../unit/utils/StdLib.sol";
import {getCoreV2} from "./../../utils/Fixtures.sol";
import {MockERC20} from "../../../../mock/MockERC20.sol";
import {MockCToken} from "../../../../mock/MockCToken.sol";
import {MockMorpho} from "../../../../mock/MockMorpho.sol";
import {IPCVDeposit} from "../../../../pcv/IPCVDeposit.sol";
import {PCVGuardian} from "../../../../pcv/PCVGuardian.sol";
import {SystemEntry} from "../../../../entry/SystemEntry.sol";
import {GenericCallMock} from "../../../../mock/GenericCallMock.sol";
import {MockPCVDepositV3} from "../../../../mock/MockPCVDepositV3.sol";
import {MockERC20, IERC20} from "../../../../mock/MockERC20.sol";
import {CompoundBadDebtSentinel} from "../../../../pcv/compound/CompoundBadDebtSentinel.sol";
import {MorphoCompoundPCVDeposit} from "../../../../pcv/morpho/MorphoCompoundPCVDeposit.sol";
import {TestAddresses as addresses} from "../../utils/TestAddresses.sol";
import {MockMorphoMaliciousReentrancy} from "../../../../mock/MockMorphoMaliciousReentrancy.sol";
import {IGlobalReentrancyLock, GlobalReentrancyLock} from "../../../../core/GlobalReentrancyLock.sol";

contract UnitTestCompoundBadDebtSentinel is Test {
    using SafeCast for *;

    event Deposit(address indexed _from, uint256 _amount);

    event Harvest(address indexed _token, int256 _profit, uint256 _timestamp);

    event Withdrawal(
        address indexed _caller,
        address indexed _to,
        uint256 _amount
    );

    CoreV2 private core;
    SystemEntry private entry;
    MockMorpho private morpho;
    PCVGuardian private pcvGuardian;
    GenericCallMock private comptroller;
    MockPCVDepositV3 private safeAddress;
    MorphoCompoundPCVDeposit private morphoDeposit;
    CompoundBadDebtSentinel private badDebtSentinel;

    uint256 public badDebtThreshold = 1_000_000e18;

    mapping(address => bool) public depositsAdded;

    /// @notice token to deposit
    MockERC20 private token;

    /// @notice global reentrancy lock
    IGlobalReentrancyLock private lock;

    /// @notice amount to deposit in morpho
    uint256 depositAmount = 100_000_000e18;

    function setUp() public {
        core = getCoreV2();
        token = new MockERC20();
        lock = IGlobalReentrancyLock(
            address(new GlobalReentrancyLock(address(core)))
        );
        morpho = new MockMorpho(IERC20(address(token)));
        comptroller = new GenericCallMock();
        safeAddress = new MockPCVDepositV3(address(core), address(token));

        morphoDeposit = new MorphoCompoundPCVDeposit(
            address(core),
            address(morpho),
            address(token),
            address(morpho),
            address(morpho)
        );
        address[] memory toWhitelist = new address[](1);
        toWhitelist[0] = address(morphoDeposit);

        address[] memory safeAddresslist = new address[](1);
        safeAddresslist[0] = address(safeAddress);

        pcvGuardian = new PCVGuardian(
            address(core),
            address(this),
            toWhitelist
        );

        badDebtSentinel = new CompoundBadDebtSentinel(
            address(core),
            address(comptroller),
            address(pcvGuardian),
            badDebtThreshold
        );

        comptroller.setResponseToCall(
            address(0),
            "",
            abi.encode(uint256(0), uint256(0), uint256(100_000e18)),
            bytes4(keccak256("getAccountLiquidity(address)"))
        );

        vm.startPrank(addresses.governorAddress);
        core.grantLocker(address(entry));
        core.grantLocker(address(pcvGuardian));
        core.grantLocker(address(morphoDeposit));
        core.grantPCVController(address(pcvGuardian));
        core.grantPCVGuard(address(this));
        core.grantGuardian(address(badDebtSentinel));
        core.setGlobalReentrancyLock(lock);
        vm.stopPrank();

        vm.label(address(morpho), "Mock Morpho Market");
        vm.label(address(token), "Token");
        vm.label(address(morphoDeposit), "Morpho PCV Deposit");
        vm.label(address(badDebtSentinel), "Bad Debt Sentinel");
    }

    function testSetup() public {
        assertEq(badDebtSentinel.pcvGuardian(), address(pcvGuardian));
        assertEq(badDebtSentinel.comptroller(), address(comptroller));
        assertEq(badDebtSentinel.badDebtThreshold(), badDebtThreshold);
    }

    function testNonGovernorCannotUpdateBadDebtThreshold(
        uint256 newThreshold
    ) public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        badDebtSentinel.updateBadDebtThreshold(newThreshold);
    }

    function testNonGovernorCannotUpdatePCVGuardian(
        address newPcvGuardian
    ) public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        badDebtSentinel.updatePCVGuardian(newPcvGuardian);
    }

    function testNonGovernorCannotAddPCVDeposits(
        address[] calldata deposits
    ) public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        badDebtSentinel.addPCVDeposits(deposits);
    }

    function testNonGovernorCannotRemovePCVDeposits(
        address[] calldata deposits
    ) public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        badDebtSentinel.removePCVDeposits(deposits);
    }

    function testGovernorCanUpdatePCVGuardian(address newPcvGuardian) public {
        vm.prank(addresses.governorAddress);
        badDebtSentinel.updatePCVGuardian(newPcvGuardian);

        assertEq(badDebtSentinel.pcvGuardian(), newPcvGuardian);
    }

    function testGovernorCanUpdateBadDebtThreshold(
        uint256 newThreshold
    ) public {
        vm.prank(addresses.governorAddress);
        badDebtSentinel.updateBadDebtThreshold(newThreshold);

        assertEq(badDebtSentinel.badDebtThreshold(), newThreshold);
    }

    function testGovernorCanAddDeposits(address[] calldata deposits) public {
        vm.prank(addresses.governorAddress);
        badDebtSentinel.addPCVDeposits(deposits);

        for (uint256 i = 0; i < deposits.length; i++) {
            assertTrue(badDebtSentinel.isCompoundPcvDeposit(deposits[i]));
        }
    }

    function _bubbleSort(
        address[] memory deposits
    ) private pure returns (uint8) {
        uint256 depositLength = deposits.length;
        if (depositLength == 0) {
            return 1;
        }

        /// do a bubble sort on input
        unchecked {
            for (uint256 i = 0; i < depositLength - 1; i++) {
                for (uint256 j = 0; j < depositLength - i - 1; j++) {
                    if (deposits[j] == deposits[j + 1]) {
                        /// if there are duplicates, return
                        return 1;
                    } else if (deposits[j] > deposits[j + 1]) {
                        address deposit = deposits[j];
                        deposits[j] = deposits[j + 1];
                        deposits[j + 1] = deposit;
                    }
                }
            }
        }

        return 0;
    }

    function testGovernorCanAddAndThenRemoveDeposits(
        address[4] memory depositsToAdd
    ) public {
        address[] memory deposits = new address[](4);
        for (uint i = 0; i < 4; i++) {
            deposits[i] = depositsToAdd[i];
        }

        if (_bubbleSort(deposits) == 1) {
            return;
        }

        vm.prank(addresses.governorAddress);
        badDebtSentinel.addPCVDeposits(deposits);
        assertEq(badDebtSentinel.allPcvDeposits().length, 4);

        for (uint256 i = 0; i < deposits.length; i++) {
            assertTrue(badDebtSentinel.isCompoundPcvDeposit(deposits[i]));
            depositsAdded[deposits[i]] = true;
        }

        address[] memory retrievedDeposits = badDebtSentinel.allPcvDeposits();

        for (uint256 i = 0; i < retrievedDeposits.length; i++) {
            assertTrue(depositsAdded[retrievedDeposits[i]]);
        }

        vm.prank(addresses.governorAddress);
        badDebtSentinel.removePCVDeposits(deposits);
        assertEq(badDebtSentinel.allPcvDeposits().length, 0);

        for (uint256 i = 0; i < deposits.length; i++) {
            assertTrue(!badDebtSentinel.isCompoundPcvDeposit(deposits[i]));
        }
    }

    function testGetTotalBadDebt(address[] calldata users) public {
        uint256 totalBadDebt = badDebtSentinel.getTotalBadDebt(users);
        assertEq(totalBadDebt, 100_000e18 * users.length);
    }

    function testNoDuplicatesAndOrdered(address[] calldata users) public {
        bool isOrdered = true;
        for (uint256 i = 0; i < users.length; i++) {
            if (depositsAdded[users[i]] == true) {
                isOrdered = false;
                break;
            }

            if (i + 1 < users.length) {
                if (users[i] >= users[i + 1]) {
                    isOrdered = false;
                    break;
                }
            }

            depositsAdded[users[i]] = true;
        }

        assertEq(isOrdered, badDebtSentinel.noDuplicatesAndOrdered(users));
    }

    function _setupRescue(address[] memory users) private returns (uint8) {
        if (_bubbleSort(users) == 1) {
            return 1;
        }

        address[] memory pcvDeposit = new address[](1);
        pcvDeposit[0] = address(morphoDeposit);

        vm.prank(addresses.governorAddress);
        badDebtSentinel.addPCVDeposits(pcvDeposit);

        deal(address(token), address(morpho), depositAmount);
        morpho.setBalance(address(morphoDeposit), depositAmount);
        token.balanceOf(address(morpho));

        return 0;
    }

    function testRescueFromCompound(address[] memory users) public {
        address[] memory pcvDeposit = new address[](1);
        pcvDeposit[0] = address(morphoDeposit);

        if (_setupRescue(users) == 1) {
            return;
        }

        badDebtSentinel.rescueFromCompound(users, pcvDeposit);

        if (users.length >= 10) {
            assertEq(morpho.balances(address(morphoDeposit)), 0);
            assertEq(token.balanceOf(address(this)), depositAmount);
        } else {
            assertEq(morpho.balances(address(morphoDeposit)), depositAmount);
            assertEq(token.balanceOf(address(this)), 0);
        }
    }

    function testRescueAllFromCompound(address[] memory users) public {
        address[] memory pcvDeposit = new address[](1);
        pcvDeposit[0] = address(morphoDeposit);

        if (_setupRescue(users) == 1) {
            return;
        }

        badDebtSentinel.rescueAllFromCompound(users);

        if (users.length >= 10) {
            assertEq(morpho.balances(address(morphoDeposit)), 0);
            assertEq(token.balanceOf(address(this)), depositAmount);
        } else {
            assertEq(morpho.balances(address(morphoDeposit)), depositAmount);
            assertEq(token.balanceOf(address(this)), 0);
        }
    }
}
