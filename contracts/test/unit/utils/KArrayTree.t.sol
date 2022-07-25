pragma solidity =0.8.13;

import {KArrayTree} from "../../integration/utils/KArrayTree.sol";
import {TribeRoles} from "../../../core/TribeRoles.sol";
import "forge-std/Test.sol";

contract KArrayTreeUnitTest is Test {
    using KArrayTree for KArrayTree.Node;

    KArrayTree.Node public tree;

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

        (bool foundGuard, KArrayTree.Node storage pcvGuard) = tree.traverse(
            TribeRoles.PCV_GUARD_ADMIN
        );
        assertTrue(foundGuard);
    }
}
