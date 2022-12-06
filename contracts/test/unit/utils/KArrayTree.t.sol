pragma solidity =0.8.13;

import {KArrayTree} from "../../integration/utils/KArrayTree.sol";
import {VoltRoles} from "../../../core/VoltRoles.sol";
import {DSTest} from "./DSTest.sol";
import {Vm} from "./Vm.sol";

contract KArrayTreeUnitTest is DSTest {
    using KArrayTree for KArrayTree.Node;

    KArrayTree.Node public tree;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    function setUp() public {
        tree.setRole(VoltRoles.GOVERN);
        tree.insert(VoltRoles.GOVERN, VoltRoles.PCV_CONTROLLER);
        tree.insert(VoltRoles.GOVERN, VoltRoles.MINTER);
        tree.insert(VoltRoles.GOVERN, VoltRoles.GUARDIAN);
    }

    function testSetup() public {
        /// tree should have a depth of 2
        /// GOVERNOR -> *
        assertEq(tree.getMaxDepth(), 2);

        /// tree should have 3 children under governor
        assertEq(tree.getCountImmediateChildren(), 3);
    }

    function testAddDuplicateFails() public {
        vm.expectRevert("cannot insert duplicate");
        tree.insert(VoltRoles.GOVERN);
    }

    function testAddDuplicateFailsFind() public {
        vm.expectRevert("cannot insert duplicate");
        tree.insert(VoltRoles.GOVERN, VoltRoles.GUARDIAN);
    }

    function testCanChangeRole() public {
        (bool foundGuard, KArrayTree.Node storage pcvGuard) = tree.traverse(
            VoltRoles.GUARDIAN
        );
        assertTrue(foundGuard);
        pcvGuard.setRole(bytes32(0));
        assertTrue(tree.exists(bytes32(0)));
    }

    function testCannotChangeToExistingRole() public {
        vm.expectRevert("cannot set duplicate");
        tree.setRole(VoltRoles.GOVERN);
    }

    function testFree() public {
        tree.free();
        assertEq(tree.getMaxDepth(), 1); /// assert the whole tree got dropped except the root node
        assertEq(tree.getCountImmediateChildren(), 0);
    }
}
