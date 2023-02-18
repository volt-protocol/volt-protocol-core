// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Vm} from "@forge-std/Vm.sol";
import {Volt} from "@voltprotocol/v1/Volt.sol";
import {IVolt} from "@voltprotocol/v1/Volt.sol";
import {ICore} from "@voltprotocol/v1/ICore.sol";
import {Test} from "@forge-std/Test.sol";
import {CoreV2} from "@voltprotocol/core/CoreV2.sol";
import {getCoreV2} from "@test/unit/utils/Fixtures.sol";
import {IPCVOracle} from "@voltprotocol/oracle/IPCVOracle.sol";
import {IGlobalRateLimitedMinter} from "@voltprotocol/rate-limits/IGlobalRateLimitedMinter.sol";
import {TestAddresses as addresses} from "@test/unit/utils/TestAddresses.sol";
import {IGlobalReentrancyLock, GlobalReentrancyLock} from "@voltprotocol/core/GlobalReentrancyLock.sol";

contract UnitTestCoreV2 is Test {
    CoreV2 private core;

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

    /// @notice emitted when reference to pcv oracle is updated
    event PCVOracleUpdate(
        address indexed oldPcvOracle,
        address indexed newPcvOracle
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
        assertEq(address(core.pcvOracle()), address(0)); /// pcv oracle starts set to address 0
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
        core.setGlobalRateLimitedMinter(IGlobalRateLimitedMinter(newGrlm));

        assertEq(address(core.globalRateLimitedMinter()), newGrlm);
    }

    function testNonGovernorFailsSettingGlobalRateLimitedMinter() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.setGlobalRateLimitedMinter(
            IGlobalRateLimitedMinter(addresses.userAddress)
        );
    }

    function testGovernorSetsPcvOracle() public {
        address newPcvOracle = address(8794534168787);
        vm.expectEmit(true, true, false, true, address(core));
        emit PCVOracleUpdate(address(0), newPcvOracle);

        vm.prank(addresses.governorAddress);
        core.setPCVOracle(IPCVOracle(newPcvOracle));

        assertEq(address(core.pcvOracle()), newPcvOracle);
    }

    function testGovernorSetsGlobalReentrancyLock() public {
        address newGlobalReentrancyLock = address(8794534168787);

        vm.prank(addresses.governorAddress);
        core.setGlobalReentrancyLock(
            IGlobalReentrancyLock(newGlobalReentrancyLock)
        );

        assertEq(address(core.globalReentrancyLock()), newGlobalReentrancyLock);
    }

    function testNonGovernorFailsSettingPCVOracle() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.setPCVOracle(IPCVOracle(addresses.userAddress));
    }

    function testNonGovernorFailsSettingGlobalReentrancyLock() public {
        vm.expectRevert("Permissions: Caller is not a governor");
        core.setGlobalReentrancyLock(
            IGlobalReentrancyLock(addresses.userAddress)
        );
    }
}
