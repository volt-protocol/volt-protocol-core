pragma solidity =0.8.13;

import {console} from "hardhat/console.sol";

import {Test} from "../../../forge-std/src/Test.sol";
import {Addresses} from "./Addresses.sol";
import {Proposal} from "./proposalTypes/Proposal.sol";

import {vip15} from "./vips/vip15.sol";
import {vip16} from "./vips/vip16.sol";
import {vip17} from "./vips/vip17.sol";

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
    uint256 public nProposals;
    bool public DEBUG;
    bool public DO_DEPLOY;
    bool public DO_AFTER_DEPLOY;
    bool public DO_RUN;
    bool public DO_TEARDOWN;
    bool public DO_VALIDATE;

    function setUp() public {
        DEBUG = vm.envOr("DEBUG", true);
        DO_DEPLOY = vm.envOr("DO_DEPLOY", true);
        DO_AFTER_DEPLOY = vm.envOr("DO_AFTER_DEPLOY", true);
        DO_RUN = vm.envOr("DO_RUN", true);
        DO_TEARDOWN = vm.envOr("DO_TEARDOWN", true);
        DO_VALIDATE = vm.envOr("DO_VALIDATE", true);
        addresses = new Addresses();

        proposals.push(Proposal(address(new vip15())));
        proposals.push(Proposal(address(new vip16())));
        proposals.push(Proposal(address(new vip17())));
        nProposals = proposals.length;
    }

    function setDebug(bool value) public {
        DEBUG = value;
        for (uint256 i = 0; i < proposals.length; i++) {
            proposals[i].setDebug(value);
        }
    }

    function testProposals()
        public
        returns (uint256[] memory postProposalVmSnapshots)
    {
        if (DEBUG) {
            console.log(
                "TestProposals: running",
                proposals.length,
                "proposals."
            );
        }
        postProposalVmSnapshots = new uint256[](proposals.length);
        for (uint256 i = 0; i < proposals.length; i++) {
            string memory name = proposals[i].name();

            // Deploy step
            if (DO_DEPLOY) {
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
            }

            // After-deploy step
            if (DO_AFTER_DEPLOY) {
                if (DEBUG) console.log("Proposal", name, "afterDeploy()");
                proposals[i].afterDeploy(addresses, address(proposals[i]));
            }

            // Run step
            if (DO_RUN) {
                if (DEBUG) console.log("Proposal", name, "run()");
                proposals[i].run(addresses, address(proposals[i]));
            }

            // Teardown step
            if (DO_TEARDOWN) {
                if (DEBUG) console.log("Proposal", name, "teardown()");
                proposals[i].teardown(addresses, address(proposals[i]));
            }

            // Validate step
            if (DO_VALIDATE) {
                if (DEBUG) console.log("Proposal", name, "validate()");
                proposals[i].validate(addresses, address(proposals[i]));
            }

            if (DEBUG) console.log("Proposal", name, "done.");

            postProposalVmSnapshots[i] = vm.snapshot();
        }

        return postProposalVmSnapshots;
    }
}
