//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {Proposal} from "../proposalTypes/Proposal.sol";
import {Addresses} from "../Addresses.sol";

contract vip00 is Proposal {
    string public name = "VIP00";

    function deploy(Addresses addresses) public pure {}

    function afterDeploy(Addresses addresses, address deployer) public pure {}

    function run(Addresses addresses, address deployer) public pure {}

    function teardown(Addresses addresses, address deployer) public pure {}

    function validate(Addresses addresses, address deployer) public pure {}
}
