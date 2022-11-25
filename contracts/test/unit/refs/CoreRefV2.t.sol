// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Vm} from "./../utils/Vm.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {ICoreV2} from "../../../core/ICoreV2.sol";
import {VoltRoles} from "../../../core/VoltRoles.sol";
import {MockERC20} from "../../../mock/MockERC20.sol";
import {IPCVOracle} from "../../../oracle/IPCVOracle.sol";
import {MockCoreRefV2} from "../../../mock/MockCoreRefV2.sol";
import {TestAddresses as addresses} from "../utils/TestAddresses.sol";
import {getCoreV2} from "./../utils/Fixtures.sol";

contract UnitTestCoreRefV2 is DSTest {
    ICoreV2 private core;
    MockCoreRefV2 private coreRef;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    event CoreUpdate(address indexed oldCore, address indexed newCore);

    function setUp() public {
        core = getCoreV2();

        coreRef = new MockCoreRefV2(address(core));

        vm.label(address(core), "Core");
        vm.label(address(coreRef), "CoreRef");
    }

    function testSetup() public {
        assertEq(
            address(coreRef.globalRateLimitedMinter()),
            address(core.globalRateLimitedMinter())
        );
        assertEq(address(coreRef.globalRateLimitedMinter()), address(0));
        assertEq(address(coreRef.volt()), address(core.volt()));
        assertEq(address(coreRef.vcon()), address(core.vcon()));
        assertEq(address(coreRef.core()), address(core));
        assertEq(address(coreRef.pcvOracle()), address(0));
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

    function testSetCoreAddressZeroGovSucceedsBricksContract() public {
        address voltAddress = address(coreRef.volt());

        vm.prank(addresses.governorAddress);
        vm.expectEmit(true, true, false, true, address(coreRef));
        emit CoreUpdate(address(core), address(0));

        coreRef.setCore(address(0));

        vm.expectRevert();
        coreRef.volt();
        vm.expectRevert();
        coreRef.vcon();
        vm.expectRevert();
        coreRef.globalRateLimitedMinter();

        vm.expectRevert();
        coreRef.sweep(voltAddress, address(this), 0);
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
        core.grantLocker(address(this));
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

    function testSweepFailsNonGovernor() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        coreRef.sweep(address(this), address(this), 0);
    }

    function testSweepSucceedsGovernor() public {
        uint256 mintAmount = 100;
        address voltAddress = address(coreRef.volt());

        MockERC20(voltAddress).mint(address(coreRef), mintAmount);

        vm.prank(addresses.governorAddress);
        coreRef.sweep(voltAddress, address(this), mintAmount);

        assertEq(MockERC20(voltAddress).balanceOf(address(this)), mintAmount);
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
            !core.isLocker(caller)
        ) {
            vm.expectRevert("UNAUTHORIZED");
        }
        vm.prank(caller);
        coreRef.testStateGovernorMinter();
    }

    function testSystemState(address caller) public {
        if (!core.isLocker(caller)) {
            vm.expectRevert("UNAUTHORIZED");
        }
        vm.prank(caller);
        coreRef.testSystemState();
    }

    function testEmergencyActionFailsNonGovernor() public {
        MockCoreRefV2.Call[] memory calls = new MockCoreRefV2.Call[](1);
        calls[0].callData = abi.encodeWithSignature(
            "transfer(address,uint256)",
            address(this),
            100
        );
        calls[0].target = address(core.volt());

        vm.expectRevert("CoreRef: Caller is not a governor");
        coreRef.emergencyAction(calls);
    }

    function testEmergencyActionSucceedsGovernor(uint256 mintAmount) public {
        MockCoreRefV2.Call[] memory calls = new MockCoreRefV2.Call[](1);
        calls[0].callData = abi.encodeWithSignature(
            "mint(address,uint256)",
            address(this),
            mintAmount
        );
        calls[0].target = address(core.volt());

        vm.prank(addresses.governorAddress);
        coreRef.emergencyAction(calls);

        assertEq(coreRef.volt().balanceOf(address(this)), mintAmount);
    }

    function testEmergencyActionSucceedsGovernorSendEth(
        uint128 sendAmount
    ) public {
        uint256 startingEthBalance = address(this).balance;

        MockCoreRefV2.Call[] memory calls = new MockCoreRefV2.Call[](1);
        calls[0].target = address(this);
        calls[0].value = sendAmount;
        vm.deal(address(coreRef), sendAmount);

        vm.prank(addresses.governorAddress);
        coreRef.emergencyAction(calls);

        uint256 endingEthBalance = address(this).balance;

        assertEq(endingEthBalance - startingEthBalance, sendAmount);
        assertEq(address(coreRef).balance, 0);
    }

    function testEmergencyActionSucceedsGovernorSendsEth(
        uint128 sendAmount
    ) public {
        MockCoreRefV2.Call[] memory calls = new MockCoreRefV2.Call[](1);
        calls[0].target = addresses.governorAddress;
        calls[0].value = sendAmount;
        vm.deal(addresses.governorAddress, sendAmount);

        vm.prank(addresses.governorAddress);
        coreRef.emergencyAction{value: sendAmount}(calls);

        uint256 endingEthBalance = addresses.governorAddress.balance;

        assertEq(endingEthBalance, sendAmount);
        assertEq(address(coreRef).balance, 0);
    }

    /// ---------- ACL ----------

    function testPauseSucceedsGovernor() public {
        assertTrue(!coreRef.paused());
        vm.prank(addresses.governorAddress);
        coreRef.pause();
        assertTrue(coreRef.paused());
    }

    function testPauseFailsNonGovernor() public {
        vm.expectRevert("CoreRef: Caller is not a guardian or governor");
        coreRef.pause();
    }

    receive() external payable {}
}
