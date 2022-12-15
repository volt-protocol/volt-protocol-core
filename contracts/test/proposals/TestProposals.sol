pragma solidity =0.8.13;

import {console} from "hardhat/console.sol";

import {Test} from "../../../forge-std/src/Test.sol";
import {Addresses} from "./Addresses.sol";
import {Proposal} from "./proposalTypes/Proposal.sol";

import {vip00} from "./vips/vip00.sol";

/*
How to use:
forge test --fork-url $ETH_RPC_URL --match-contract TestProposals -vvv

Or, from another Solidity file (for post-proposal integration testing):
    TestProposals proposals = new TestProposals();
    proposals.setUp();
    proposals.setDebug(false); // don't console.log
    proposals.testProposals();
    Addresses addresses = proposals.addresses();
*/

contract TestProposals is Test {
    Addresses public addresses;
    Proposal[] public proposals;
    bool public DEBUG = true;

    function setUp() public {
        addresses = new Addresses();

        proposals.push(Proposal(address(new vip00())));
    }

    function setDebug(bool value) public {
        DEBUG = value;
        for (uint256 i = 0; i < proposals.length; i++) {
            proposals[i].setDebug(value);
        }
    }

    function testProposals() public {
        if (DEBUG)
            console.log(
                "TestProposals: running",
                proposals.length,
                "proposals."
            );
        for (uint256 i = 0; i < proposals.length; i++) {
            string memory name = proposals[i].name();

            // Deploy step
            if (DEBUG) {
                console.log("Proposal", name, "deploy()");
                addresses.resetRecordingAddresses();
            }
            proposals[i].deploy(addresses);
            if (DEBUG) {
                (
                    string[] memory recordedNames,
                    address[] memory recordedAddresses
                ) = addresses.getRecordedAddresses();
                for (uint256 j = 0; j < recordedNames.length; j++) {
                    console.log(
                        "  Deployed",
                        recordedAddresses[j],
                        recordedNames[j]
                    );
                }
            }

            // After-deploy step
            if (DEBUG) console.log("Proposal", name, "afterDeploy()");
            proposals[i].afterDeploy(addresses, address(proposals[i]));

            // Run step
            if (DEBUG) console.log("Proposal", name, "run()");
            proposals[i].run(addresses, address(proposals[i]));

            // Teardown step
            if (DEBUG) console.log("Proposal", name, "teardown()");
            proposals[i].teardown(addresses, address(proposals[i]));

            // Validate step
            if (DEBUG) console.log("Proposal", name, "validate()");
            proposals[i].validate(addresses, address(proposals[i]));

            if (DEBUG) console.log("Proposal", name, "done.");
        }
    }
}
