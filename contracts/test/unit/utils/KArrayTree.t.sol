pragma solidity =0.8.13;

import {KArrayTree} from "../../integration/utils/KArrayTree.sol";
import {TribeRoles} from "../../../core/TribeRoles.sol";
import {DSTest} from "./DSTest.sol";
import {Vm} from "./Vm.sol";

contract KArrayTreeUnitTest is DSTest {
    using KArrayTree for KArrayTree.Node;

    KArrayTree.Node public tree;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    function setUp() public {
        tree.setRole(TribeRoles.GOVERNOR);
        tree.insert(TribeRoles.GOVERNOR, TribeRoles.PCV_CONTROLLER);
        tree.insert(TribeRoles.GOVERNOR, TribeRoles.MINTER);
        tree.insert(TribeRoles.GOVERNOR, TribeRoles.GUARDIAN);
        tree.insert(TribeRoles.GOVERNOR, TribeRoles.PCV_GUARD_ADMIN);
        tree.insert(TribeRoles.PCV_GUARD_ADMIN, TribeRoles.PCV_GUARD);
    }

    function testSetup() public {
        /// tree should have a depth of 3
        /// GOVERNOR -> PCV GUARD ADMIN -> PCV GUARD
        assertEq(tree.getMaxDepth(), 3);

        /// tree should have 4 children under governor
        assertEq(tree.getCountImmediateChildren(), 4);

        /// tree should have 1 child under PCV GUARD ADMIN
        (bool found, KArrayTree.Node storage pcvGuardAdmin) = tree.traverse(
            TribeRoles.PCV_GUARD_ADMIN
        );
        assertTrue(found);
        assertEq(pcvGuardAdmin.getCountImmediateChildren(), 1);

        (bool foundGuard, ) = tree.traverse(TribeRoles.PCV_GUARD);
        assertTrue(foundGuard);
    }

    function testAddDuplicateFails() public {
        vm.expectRevert("cannot insert duplicate");
        tree.insert(TribeRoles.GOVERNOR);
    }

    function testAddDuplicateFailsFind() public {
        vm.expectRevert("cannot insert duplicate");
        tree.insert(TribeRoles.GOVERNOR, TribeRoles.PCV_GUARD);
    }

    function testCanChangeRole() public {
        (bool foundGuard, KArrayTree.Node storage pcvGuard) = tree.traverse(
            TribeRoles.PCV_GUARD_ADMIN
        );
        assertTrue(foundGuard);
        pcvGuard.setRole(bytes32(0));
        assertTrue(tree.exists(bytes32(0)));
    }

    function testCannotChangeToExistingRole() public {
        vm.expectRevert("cannot set duplicate");
        tree.setRole(TribeRoles.GOVERNOR);
    }

    function testFree() public {
        tree.free();
        assertEq(tree.getMaxDepth(), 1); /// assert the whole tree got dropped except the root node
        assertEq(tree.getCountImmediateChildren(), 0);
    }
}
