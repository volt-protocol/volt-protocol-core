// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {PCVGuardian} from "../../pcv/PCVGuardian.sol";
import {TribeRoles} from "../../core/TribeRoles.sol";
import {ICore} from "../../core/ICore.sol";
import {IVolt} from "../../volt/Volt.sol";
import {IPCVDeposit} from "../../pcv/IPCVDeposit.sol";

import {DSTest} from "../unit/utils/DSTest.sol";
import {Vm} from "../unit/utils/Vm.sol";

contract IntegrationTestPCVGuardian is DSTest {
    PCVGuardian private pcvGuardian;

    ICore private core = ICore(0xEC7AD284f7Ad256b64c6E69b84Eb0F48f42e8196);
    IVolt private fei = IVolt(0x956F47F50A910163D8BF957Cf5846D573E7f87CA);

    IPCVDeposit private pcvDeposit =
        IPCVDeposit(0x4188fbD7aDC72853E3275F1c3503E170994888D7);

    Vm public constant vm = Vm(HEVM_ADDRESS);

    address public voltDeployer = 0x25dCffa22EEDbF0A69F6277e24C459108c186ecB;

    address[] public whitelistAddresses;
    address public guard = address(0x123456789);

    uint256 public withdrawAmount = 23_000e18; // approximate amount deposited at this block time

    function setUp() public {
        whitelistAddresses.push(address(pcvDeposit));

        pcvGuardian = new PCVGuardian(
            address(core),
            address(this), // using 'this' address as the safe address for withdrawals
            whitelistAddresses
        );

        // grant the pcvGuardian the PCV controller and Guardian roles
        vm.startPrank(voltDeployer);
        core.grantPCVController(address(pcvGuardian));
        core.grantGuardian(address(pcvGuardian));

        // create the PCV guard role, and grant it to the 'guard' address
        core.createRole(TribeRoles.PCV_GUARD, TribeRoles.GOVERNOR);
        core.grantRole(TribeRoles.PCV_GUARD, guard);
        vm.stopPrank();
    }

    function testPCVGuardianRoles() public view {
        assert(core.isGuardian(address(pcvGuardian)));
        assert(core.isPCVController(address(pcvGuardian)));
    }

    function testGovernorWithdrawToSafeAddress() public {
        vm.prank(voltDeployer);
        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), withdrawAmount);

        assertEq(fei.balanceOf(address(this)), withdrawAmount);
    }

    function testGuardianWithdrawToSafeAddress() public {
        vm.prank(voltDeployer);
        core.grantGuardian(address(0x1234));

        vm.prank(address(0x1234));
        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), withdrawAmount);

        assertEq(fei.balanceOf(address(this)), withdrawAmount);
    }

    function testGuardWithdrawToSafeAddress() public {
        vm.startPrank(guard);
        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), withdrawAmount);

        assertEq(fei.balanceOf(address(this)), withdrawAmount);
    }

    function testWithdrawToSafeAddressFailWhenNoRole() public {
        vm.expectRevert(bytes("UNAUTHORIZED"));
        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), withdrawAmount);
    }

    function testWithdrawToSafeAddressFailWhenNotWhitelist() public {
        vm.prank(voltDeployer);
        vm.expectRevert(bytes("Provided address is not whitelisted"));

        pcvGuardian.withdrawToSafeAddress(address(0x1), withdrawAmount);
    }

    function testWithdrawToSafeAddressFailWhenGuardRevoked() public {
        vm.prank(voltDeployer);
        core.revokeRole(TribeRoles.PCV_GUARD, guard);

        vm.prank(guard);
        vm.expectRevert(bytes("UNAUTHORIZED"));

        pcvGuardian.withdrawToSafeAddress(address(pcvDeposit), withdrawAmount);
    }

    function testSetWhiteListAddress() public {
        vm.prank(voltDeployer);

        pcvGuardian.setWhitelistAddress(address(0x123));
        assert(pcvGuardian.isWhitelistAddress(address(0x123)));
    }

    function testUnsetWhiteListAddress() public {
        vm.prank(voltDeployer);

        pcvGuardian.unsetWhitelistAddress(address(pcvDeposit));
        assert(!pcvGuardian.isWhitelistAddress(address(pcvDeposit)));
    }
}
