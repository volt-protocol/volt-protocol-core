// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Vm} from "./../utils/Vm.sol";
import {Volt} from "../../../volt/Volt.sol";
import {Vcon} from "../../../vcon/Vcon.sol";
import {IVolt} from "../../../volt/Volt.sol";
import {ICore} from "../../../core/ICore.sol";
import {IGRLM} from "../../../minter/IGRLM.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {CoreV2} from "../../../core/CoreV2.sol";
import {TestAddresses as addresses} from "../utils/TestAddresses.sol";
import {getCoreV2} from "./../utils/Fixtures.sol";

contract UnitTestCoreV2 is DSTest {
    CoreV2 private core;

    Vm public constant vm = Vm(HEVM_ADDRESS);
    address volt;
    address vcon;

    /// @notice emitted with reference to VOLT token is updated
    event VoltUpdate(address indexed oldVolt, address indexed newVolt);

    /// @notice emitted when reference to VCON token is updated
    event VconUpdate(address indexed oldVcon, address indexed newVcon);

    /// @notice emitted when reference to global rate limited minter is updated
    event GlobalRateLimitedMinterUpdate(
        address indexed oldGrlm,
        address indexed newGrlm
    );

    function setUp() public {
        core = getCoreV2();
        vcon = address(core.vcon());
        volt = address(core.volt());
    }

    function testSetup() public {
        assertEq(address(core.volt()), volt);
        assertEq(address(core.vcon()), vcon); /// vcon starts set to address 0
        assertEq(address(core.globalRateLimitedMinter()), address(0)); /// global rate limited minter starts set to address 0
    }

    function testGovernorSetsVolt() public {
        vm.expectEmit(true, true, false, true, address(core));
        emit VoltUpdate(volt, addresses.userAddress);

        vm.prank(addresses.governorAddress);
        core.setVolt(IVolt(address(addresses.userAddress)));

        assertEq(address(core.volt()), addresses.userAddress);
    }

    function testNonGovernorFailsSettingVolt() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.setVolt(IVolt(address(addresses.userAddress)));
    }

    function testGovernorSetsVcon() public {
        vm.expectEmit(true, true, false, true, address(core));
        emit VconUpdate(vcon, addresses.userAddress);

        vm.prank(addresses.governorAddress);
        core.setVcon(IERC20(addresses.userAddress));

        assertEq(address(core.vcon()), addresses.userAddress);
    }

    function testNonGovernorFailsSettingVcon() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.setVcon(IERC20(addresses.userAddress));
    }

    function testGovernorSetsGlobalRateLimitedMinter() public {
        address newGrlm = address(103927828732);
        vm.expectEmit(true, true, false, true, address(core));
        emit GlobalRateLimitedMinterUpdate(address(0), newGrlm);

        vm.prank(addresses.governorAddress);
        core.setGlobalRateLimitedMinter(IGRLM(newGrlm));

        assertEq(address(core.globalRateLimitedMinter()), newGrlm);
    }

    function testNonGovernorFailsSettingGlobalRateLimitedMinter() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.setGlobalRateLimitedMinter(IGRLM(addresses.userAddress));
    }
}
