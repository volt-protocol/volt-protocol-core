// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "hardhat/console.sol";

import {vip00 as vip} from "./vips/vip00.sol";
import {Script} from "../../../forge-std/src/Script.sol";
import {Addresses} from "./Addresses.sol";

/*
How to use:
1/ Update the PRIVATE_KEY variable in this script to read the proper env variable
2/ Configure DO_DEPLOY, DO_AFTERDEPLOY, DO_TEARDOWN in this file as needed
2/ Import and inherit the proper VIP proposal script
3/ Run the following command, with correct RPC url :
forge script contracts/test/proposals/DeployProposal.s.sol:DeployProposal \
    -vvvv \
    --rpc-url $LOCAL_RPC_URL \
    --broadcast
Remove --broadcast if you want to try locally first, without paying any gas.
*/

contract DeployProposal is Script, vip {
    uint256 public PRIVATE_KEY = vm.envUint("ANVIL0_PRIVATE_KEY");
    bool public DO_DEPLOY = true;
    bool public DO_AFTERDEPLOY = true;
    bool public DO_TEARDOWN = false;

    function setUp() public {}

    function run() public {
        Addresses addresses = new Addresses();
        addresses.resetRecordingAddresses();
        address deployerAddress = vm.addr(PRIVATE_KEY);

        vm.startBroadcast(PRIVATE_KEY);
        if (DO_DEPLOY) deploy(addresses);
        if (DO_AFTERDEPLOY) afterDeploy(addresses, deployerAddress);
        if (DO_TEARDOWN) teardown(addresses, deployerAddress);
        vm.stopBroadcast();

        if (DO_DEPLOY) {
            (
                string[] memory recordedNames,
                address[] memory recordedAddresses
            ) = addresses.getRecordedAddresses();
            for (uint256 i = 0; i < recordedNames.length; i++) {
                console.log("Deployed", recordedAddresses[i], recordedNames[i]);
            }
        }
    }
}
