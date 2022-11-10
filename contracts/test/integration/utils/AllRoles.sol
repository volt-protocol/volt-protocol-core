// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {Vm} from "./../../unit/utils/Vm.sol";
import {Core} from "../../../core/Core.sol";
import {VoltRoles} from "../../../core/VoltRoles.sol";
import {RoleTesting} from "./RoleTesting.sol";
import {AllRolesConfig} from "./AllRolesConfig.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {ArbitrumAddresses} from "../fixtures/ArbitrumAddresses.sol";

contract AllRoles is RoleTesting, AllRolesConfig {
    /// System should look the same in terms of who has roles, and what roles exist
    /// on both mainnet and arbitrum
    function _setupMainnet(Core core) internal {
        /// wipe the slate clean before each test
        delete numEachRole;

        for (uint256 i = 0; i < allAddresses.length; i++) {
            delete allAddresses[i];
        }

        for (uint256 i = 0; i < allRoles.length; i++) {
            numEachRole.push(core.getRoleMemberCount(allRoles[i]));
        }

        allAddresses[0].push(MainnetAddresses.CORE);
        allAddresses[0].push(MainnetAddresses.GOVERNOR);
        allAddresses[0].push(MainnetAddresses.TIMELOCK_CONTROLLER);

        allAddresses[1].push(MainnetAddresses.PCV_GUARDIAN);

        allAddresses[2].push(MainnetAddresses.GOVERNOR);
        allAddresses[2].push(MainnetAddresses.PCV_GUARDIAN);
        allAddresses[2].push(MainnetAddresses.ERC20ALLOCATOR);
        allAddresses[2].push(MainnetAddresses.COMPOUND_PCV_ROUTER);

        allAddresses[4].push(MainnetAddresses.EOA_1);
        allAddresses[4].push(MainnetAddresses.EOA_2);
        allAddresses[4].push(MainnetAddresses.EOA_3);

        allAddresses[5].push(MainnetAddresses.PCV_GUARD_ADMIN);
    }

    function _setupArbitrum(Core core) internal {
        /// wipe the slate clean before each test
        delete numEachRole;

        for (uint256 i = 0; i < allAddresses.length; i++) {
            delete allAddresses[i];
        }

        for (uint256 i = 0; i < allRoles.length; i++) {
            numEachRole.push(core.getRoleMemberCount(allRoles[i]));
        }

        allAddresses[0].push(ArbitrumAddresses.CORE);
        allAddresses[0].push(ArbitrumAddresses.GOVERNOR);
        allAddresses[0].push(ArbitrumAddresses.TIMELOCK_CONTROLLER);

        allAddresses[1].push(ArbitrumAddresses.PCV_GUARDIAN);

        allAddresses[2].push(ArbitrumAddresses.GOVERNOR);
        allAddresses[2].push(ArbitrumAddresses.PCV_GUARDIAN);
        allAddresses[2].push(MainnetAddresses.ERC20ALLOCATOR);
        allAddresses[2].push(MainnetAddresses.COMPOUND_PCV_ROUTER);

        allAddresses[4].push(ArbitrumAddresses.EOA_1);
        allAddresses[4].push(ArbitrumAddresses.EOA_2);
        allAddresses[4].push(ArbitrumAddresses.EOA_3);

        allAddresses[5].push(ArbitrumAddresses.PCV_GUARD_ADMIN);

        /// sanity check
        assert(numEachRole.length == allRoles.length);
    }

    /// load up number of roles from Core and ensure that they match up with numbers here
    function testRoleArity() public {
        if (block.chainid == 42161) {
            _setupArbitrum(Core(ArbitrumAddresses.CORE));
        } else if (block.chainid == 1) {
            _setupMainnet(Core(MainnetAddresses.CORE));
        }
        _testRoleArity(getAllRoles(), roleCounts, numEachRole);
    }

    /// assert that all addresses have the proper role
    function testRoleAddresses(Core core) public {
        _testRoleAddresses(getAllRoles(), allAddresses, core);
    }
}
