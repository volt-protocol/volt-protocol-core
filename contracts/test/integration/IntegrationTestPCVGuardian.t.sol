// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Vm} from "../unit/utils/Vm.sol";
import {ICore} from "../../core/ICore.sol";
import {IVolt} from "../../volt/Volt.sol";
import {DSTest} from "../unit/utils/DSTest.sol";
import {VoltRoles} from "../../core/VoltRoles.sol";
import {IPCVDeposit} from "../../pcv/IPCVDeposit.sol";
import {PCVGuardian} from "../../pcv/PCVGuardian.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {getMainnetAddresses, VoltTestAddresses} from "../unit/utils/Fixtures.sol";

interface IPCVDepositTest is IPCVDeposit {
    function pause() external;

    function paused() external view returns (bool);
}

contract IntegrationTestPCVGuardian is DSTest {
    PCVGuardian private pcvGuardian;

    ICore private core = ICore(MainnetAddresses.CORE);
    IVolt private fei = IVolt(MainnetAddresses.FEI);

    IPCVDepositTest private pcvDeposit =
        IPCVDepositTest(MainnetAddresses.VOLT_FEI_PSM);

    Vm public constant vm = Vm(HEVM_ADDRESS);

    address[] public whitelistAddresses;
    address public guard = address(0x123456789);

    uint256 public withdrawAmount = fei.balanceOf(address(pcvDeposit));

    function setUp() public {
        whitelistAddresses.push(address(pcvDeposit));

        pcvGuardian = new PCVGuardian(
            address(core),
            address(this), // using 'this' address as the safe address for withdrawals
            whitelistAddresses
        );

        // grant the pcvGuardian the PCV controller and Guardian roles
        vm.startPrank(MainnetAddresses.GOVERNOR);
        core.grantPCVController(address(pcvGuardian));
        core.grantGuardian(address(pcvGuardian));

        /// create the PCV_GUARD role
        core.createRole(VoltRoles.PCV_GUARD, VoltRoles.GOVERNOR);

        /// grant it to the 'guard' address
        core.grantRole(VoltRoles.PCV_GUARD, guard);
        vm.stopPrank();
    }

    function testPCVGuardianRoles() public {
        assertTrue(core.isGuardian(address(pcvGuardian)));
        assertTrue(core.isPCVController(address(pcvGuardian)));
    }

    function testPCVGuardRole() public {
        assertTrue(core.hasRole(VoltRoles.PCV_GUARD, guard));
    }

    function testPausedAfterWithdrawToSafeAddress() public {
        vm.startPrank(MainnetAddresses.GOVERNOR);
        pcvDeposit.pause();
        assertEq(fei.balanceOf(address(this)), 0);

        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), withdrawAmount);
        vm.stopPrank();

        assertEq(fei.balanceOf(address(this)), withdrawAmount);
        assertTrue(pcvDeposit.paused());
    }

    function testGovernorWithdrawToSafeAddress() public {
        vm.startPrank(MainnetAddresses.GOVERNOR);
        assertEq(fei.balanceOf(address(this)), 0);

        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), withdrawAmount);
        vm.stopPrank();

        assertEq(fei.balanceOf(address(this)), withdrawAmount);
    }

    function testPausedAfterWithdrawAllToSafeAddress() public {
        vm.startPrank(MainnetAddresses.GOVERNOR);
        pcvDeposit.pause();
        assertEq(fei.balanceOf(address(this)), 0);

        uint256 amountToWithdraw = pcvDeposit.balance();
        pcvGuardian.withdrawAllToSafeAddress(address(pcvDeposit));
        vm.stopPrank();

        assertEq(fei.balanceOf(address(this)), amountToWithdraw);
        assertTrue(pcvDeposit.paused());
    }

    function testGovernorWithdrawAllToSafeAddress() public {
        vm.startPrank(MainnetAddresses.GOVERNOR);
        assertEq(fei.balanceOf(address(this)), 0);

        uint256 amountToWithdraw = pcvDeposit.balance();
        pcvGuardian.withdrawAllToSafeAddress(address(pcvDeposit));
        vm.stopPrank();

        assertEq(fei.balanceOf(address(this)), amountToWithdraw);
    }

    function testGuardianWithdrawToSafeAddress() public {
        vm.startPrank(MainnetAddresses.PCV_GUARDIAN);

        assertEq(fei.balanceOf(address(this)), 0);
        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), withdrawAmount);

        vm.stopPrank();

        assertEq(fei.balanceOf(address(this)), withdrawAmount);
    }

    function testGuardianWithdrawAllToSafeAddress() public {
        vm.startPrank(MainnetAddresses.PCV_GUARDIAN);

        assertEq(fei.balanceOf(address(this)), 0);
        uint256 amountToWithdraw = pcvDeposit.balance();

        pcvGuardian.withdrawAllToSafeAddress(address(pcvDeposit));
        vm.stopPrank();

        assertEq(fei.balanceOf(address(this)), amountToWithdraw);
    }

    function testGuardWithdrawToSafeAddress() public {
        vm.startPrank(guard);
        assertEq(fei.balanceOf(address(this)), 0);
        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), withdrawAmount);

        assertEq(fei.balanceOf(address(this)), withdrawAmount);
    }

    function testGuardWithdrawAllToSafeAddress() public {
        vm.startPrank(guard);

        assertEq(fei.balanceOf(address(this)), 0);
        uint256 amountToWithdraw = pcvDeposit.balance();

        pcvGuardian.withdrawAllToSafeAddress(address(pcvDeposit));
        vm.stopPrank();

        assertEq(fei.balanceOf(address(this)), amountToWithdraw);
    }

    function testWithdrawToSafeAddressFailWhenNoRole() public {
        vm.expectRevert(bytes("UNAUTHORIZED"));
        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), withdrawAmount);
    }

    function testWithdrawAllToSafeAddressFailWhenNoRole() public {
        vm.expectRevert(bytes("UNAUTHORIZED"));
        pcvGuardian.withdrawAllToSafeAddress(address(pcvDeposit));
    }

    function testWithdrawToSafeAddressFailWhenNotWhitelist() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        vm.expectRevert(
            bytes("PCVGuardian: Provided address is not whitelisted")
        );

        pcvGuardian.withdrawToSafeAddress(address(0x1), withdrawAmount);
    }

    function testWithdrawAllToSafeAddressFailWhenNotWhitelist() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        vm.expectRevert(
            bytes("PCVGuardian: Provided address is not whitelisted")
        );

        pcvGuardian.withdrawAllToSafeAddress(address(0x1));
    }

    function testWithdrawToSafeAddressFailWhenGuardRevokedGovernor() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        core.revokeRole(VoltRoles.PCV_GUARD, guard);

        vm.prank(guard);
        vm.expectRevert(bytes("UNAUTHORIZED"));

        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), withdrawAmount);
    }

    function testWithdrawAllToSafeAddressFailWhenGuardRevokedGovernor() public {
        vm.prank(MainnetAddresses.GOVERNOR);
        core.revokeRole(VoltRoles.PCV_GUARD, guard);

        vm.prank(guard);
        vm.expectRevert(bytes("UNAUTHORIZED"));

        pcvGuardian.withdrawAllToSafeAddress(address(pcvDeposit));
    }

    function testSetWhiteListAddress() public {
        vm.prank(MainnetAddresses.GOVERNOR);

        pcvGuardian.addWhitelistAddress(address(0x123));
        assertTrue(pcvGuardian.isWhitelistAddress(address(0x123)));
    }

    function testUnsetWhiteListAddress() public {
        vm.prank(MainnetAddresses.GOVERNOR);

        pcvGuardian.removeWhitelistAddress(address(pcvDeposit));
        assertTrue(!pcvGuardian.isWhitelistAddress(address(pcvDeposit)));
    }
}
