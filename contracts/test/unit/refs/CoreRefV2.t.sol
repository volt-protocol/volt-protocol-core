pragma solidity 0.8.13;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {Vm} from "./../utils/Vm.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {ICoreV2} from "../../../core/ICoreV2.sol";
import {VoltRoles} from "../../../core/VoltRoles.sol";
import {MockCoreRefV2} from "../../../mock/MockCoreRefV2.sol";
import {getCoreV2, getAddresses, VoltTestAddresses} from "./../utils/Fixtures.sol";

contract UnitTestCoreRefV2 is DSTest {
    ICoreV2 private core;
    MockCoreRefV2 private coreRef;
    Vm public constant vm = Vm(HEVM_ADDRESS);
    VoltTestAddresses public addresses = getAddresses();

    event CoreUpdate(address indexed oldCore, address indexed newCore);

    function setUp() public {
        core = getCoreV2();

        coreRef = new MockCoreRefV2(address(core));

        vm.label(address(core), "Core");
        vm.label(address(coreRef), "CoreRef");
    }

    function testSetup() public {
        assertEq(address(coreRef.core()), address(core));
        assertTrue(address(coreRef.volt()) != address(0));
        assertTrue(address(coreRef.vcon()) != address(0));

        assertEq(address(coreRef.volt()), address(core.volt()));
        assertEq(address(coreRef.vcon()), address(core.vcon()));
    }

    function testRandomsCannotCreateRole(address sender, bytes32 role) public {
        vm.assume(!core.hasRole(VoltRoles.GOVERNOR, sender));
        vm.prank(sender);

        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(sender), 20),
                " is missing role ",
                Strings.toHexString(uint256(0), 32)
            )
        );
        core.grantRole(role, sender);
    }

    function testMinter(address caller) public {
        vm.startPrank(caller);

        if (!core.isMinter(caller)) {
            vm.expectRevert("CoreRef: Caller is not a minter");
        }
        coreRef.testMinter();
        vm.stopPrank();
    }

    function testSetCoreGovSucceeds() public {
        ICoreV2 core2 = getCoreV2();
        vm.prank(addresses.governorAddress);

        vm.expectEmit(true, true, false, true, address(coreRef));
        emit CoreUpdate(address(core), address(core2));

        coreRef.setCore(address(core2));

        assertEq(address(coreRef.core()), address(core2));

        assertTrue(address(coreRef.volt()) != address(core.volt()));
        assertTrue(address(coreRef.vcon()) != address(core.vcon()));
    }

    function testSetCoreToAddress0GovSucceeds() public {
        vm.prank(addresses.governorAddress);

        vm.expectEmit(true, true, false, true, address(coreRef));
        emit CoreUpdate(address(core), address(0));

        coreRef.setCore(address(0));

        assertEq(address(coreRef.core()), address(0));

        /// after setting core to address(0), all calls fail
        vm.expectRevert();
        coreRef.volt();

        vm.expectRevert();
        coreRef.vcon();

        vm.prank(addresses.governorAddress);
        vm.expectRevert();
        coreRef.setCore(address(core));
    }

    function testSetCoreNonGovFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        coreRef.setCore(address(0));

        assertEq(address(coreRef.core()), address(core));
    }

    function testMinterAsMinter() public {
        vm.prank(addresses.minterAddress);
        coreRef.testMinter();
    }

    function testGovernorAsGovernor() public {
        vm.prank(addresses.governorAddress);
        coreRef.testGovernor();
    }

    function testPCVControllerAsPCVController() public {
        vm.prank(addresses.pcvControllerAddress);
        coreRef.testPCVController();
    }

    function testStateAsState() public {
        vm.prank(addresses.governorAddress);
        core.grantRole(VoltRoles.SYSTEM_STATE_ROLE, address(this));
        coreRef.testSystemState();
    }

    function testGuardianAsGuardian() public {
        vm.prank(addresses.guardianAddress);
        coreRef.testGuardian();
    }

    function testPCVController(address caller) public {
        if (!core.isPCVController(caller)) {
            vm.expectRevert("CoreRef: Caller is not a PCV controller");
        }
        vm.prank(caller);
        coreRef.testPCVController();
    }

    function testGovernor(address caller) public {
        if (!core.isGovernor(caller)) {
            vm.expectRevert("CoreRef: Caller is not a governor");
        }
        vm.prank(caller);
        coreRef.testGovernor();
    }

    function testGuardian(address caller) public {
        if (!core.isGovernor(caller) && !core.isGuardian(caller)) {
            vm.expectRevert("CoreRef: Caller is not a guardian or governor");
        }
        vm.prank(caller);
        coreRef.testGuardian();
    }

    function testStateGovernorMinter(address caller) public {
        if (
            !core.isGovernor(caller) &&
            !core.isMinter(caller) &&
            !core.hasRole(VoltRoles.SYSTEM_STATE_ROLE, caller)
        ) {
            vm.expectRevert("UNAUTHORIZED");
        }
        vm.prank(caller);
        coreRef.testStateGovernorMinter();
    }

    function testSystemState(address caller) public {
        if (!core.hasRole(VoltRoles.SYSTEM_STATE_ROLE, caller)) {
            vm.expectRevert("UNAUTHORIZED");
        }
        vm.prank(caller);
        coreRef.testSystemState();
    }
}
