//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TimelockSimulation} from "../utils/TimelockSimulation.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {ArbitrumAddresses} from "../fixtures/ArbitrumAddresses.sol";
import {DSTest} from "./../../unit/utils/DSTest.sol";
import {Core} from "../../../core/Core.sol";
import {Vm} from "./../../unit/utils/Vm.sol";
import {IVIP} from "./IVIP.sol";
import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";

contract vip9 is DSTest, IVIP {
    using SafeERC20 for IERC20;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    uint256 public startingFeiBalance;

    function getMainnetProposal()
        public
        pure
        override
        returns (TimelockSimulation.action[] memory proposal)
    {
        proposal = new TimelockSimulation.action[](1);

        address[] memory toWhitelist = new address[](3);
        // toWhitelist[0] = address(daiDeposit);
        // toWhitelist[1] = address(feiDeposit);
        // toWhitelist[2] = address(usdcDeposit);

        proposal[0].target = MainnetAddresses.PCV_GUARDIAN;
        proposal[0].value = 0;
        proposal[0].arguments = abi.encodeWithSignature(
            "addWhitelistAddresses(address[])",
            toWhitelist
        );
        proposal[0].description = "Pause redemptions on the FEI PSM";
    }

    function mainnetSetup() public override {}

    function mainnetValidate() public override {
        // assertTrue(
        //     PCVGuardian(MainnetAddresses.PCV_GUARDIAN).isWhitelistAddress(pcvDeposit)
        // );
        // assertTrue(
        //     PCVGuardian(MainnetAddresses.PCV_GUARDIAN).isWhitelistAddress(pcvDeposit)
        // );
        // assertTrue(
        //     PCVGuardian(MainnetAddresses.PCV_GUARDIAN).isWhitelistAddress(pcvDeposit)
        // );
        // assertEq(address(daiDeposit.core()), address(core));
        // assertEq(address(feiDeposit.core()), address(core));
        // assertEq(address(usdcDeposit.core()), address(core));
        // assertEq(address(daiDeposit.cToken()), address(MainnetAddresses.CDAI));
        // assertEq(address(feiDeposit.cToken()), address(MainnetAddresses.CFEI));
        // assertEq(address(usdcDeposit.cToken()), address(MainnetAddresses.CUSDC));
        // assertEq(address(daiDeposit.token()), address(MainnetAddresses.DAI));
        // assertEq(address(feiDeposit.token()), address(MainnetAddresses.FEI));
        // assertEq(address(usdcDeposit.token()), address(MainnetAddresses.USDC));
    }

    /// prevent errors by reverting on arbitrum proposal functions being called on this VIP
    function getArbitrumProposal()
        public
        pure
        override
        returns (TimelockSimulation.action[] memory)
    {
        revert("no arbitrum proposal");
    }

    function arbitrumSetup() public override {
        revert("no arbitrum proposal");
    }

    function arbitrumValidate() public override {
        revert("no arbitrum proposal");
    }
}
