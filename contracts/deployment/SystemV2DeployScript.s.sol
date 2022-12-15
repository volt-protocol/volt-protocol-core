// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Script} from "../../forge-std/src/Script.sol";
import {SystemV2} from "./SystemV2.sol";
import "hardhat/console.sol";

/*
forge script contracts/deployment/SystemV2DeployScript.s.sol:SystemV2DeployScript \
    -vvvv \
    --rpc-url $ANVIL_RPC_URL \
    --broadcast
*/

contract SystemV2DeployScript is Script, SystemV2 {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("ANVIL0_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);
        deploy();
        setUp(deployerAddress);
        vm.stopBroadcast();

        // Print deployed addresses
        console.log("Deployed addresses :");
        console.log("CORE =", address(core));
        console.log("VOLT =", address(volt));
        console.log("TIMELOCK_CONTROLLER =", address(timelockController));
        console.log("GLOBAL_RATE_LIMITED_MINTER =", address(grlm));
        console.log("GLOBAL_SYSTEM_EXIT_RATE_LIMITER =", address(gserl));
        console.log("VOLT_SYSTEM_ORACLE =", address(vso));
        console.log("PCV_DEPOSIT_MORPHO_DAI =", address(morphoDaiPCVDeposit));
        console.log("PCV_DEPOSIT_MORPHO_USDC =", address(morphoUsdcPCVDeposit));
        console.log("PSM_DAI =", address(daipsm));
        console.log("PSM_USDC =", address(usdcpsm));
        console.log("PSM_NONCUSTODIAL_USDC =", address(usdcNonCustodialPsm));
        console.log("PSM_NONCUSTODIAL_DAI =", address(daiNonCustodialPsm));
        console.log("PSM_ALLOCATOR =", address(allocator));
        console.log("SYSTEM_ENTRY =", address(systemEntry));
        console.log("PCV_SWAPPER_MAKER =", address(pcvSwapperMaker));
        console.log("PCV_GUARDIAN =", address(pcvGuardian));
        console.log("PCV_ROUTER =", address(pcvRouter));
        console.log("PCV_ORACLE =", address(pcvOracle));
        console.log("ORACLE_CONSTANT_DAI =", address(daiConstantOracle));
        console.log("ORACLE_CONSTANT_USDC =", address(usdcConstantOracle));
    }
}
