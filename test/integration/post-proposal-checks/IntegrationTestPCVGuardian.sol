// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {PostProposalCheck} from "@test/integration/post-proposal-checks/PostProposalCheck.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PCVGuardian} from "@voltprotocol/pcv/PCVGuardian.sol";
import {IPCVDepositV2} from "@voltprotocol/pcv/IPCVDepositV2.sol";

contract IntegrationTestPCVGuardian is PostProposalCheck {
    function testWithdrawAllToSafeAddress() public {
        address[8] memory addressesToClean = [
            addresses.mainnet("PSM_DAI"),
            addresses.mainnet("PSM_USDC"),
            addresses.mainnet("PCV_DEPOSIT_MORPHO_COMPOUND_DAI"),
            addresses.mainnet("PCV_DEPOSIT_MORPHO_COMPOUND_USDC"),
            addresses.mainnet("PCV_DEPOSIT_EULER_DAI"),
            addresses.mainnet("PCV_DEPOSIT_EULER_USDC"),
            addresses.mainnet("PCV_DEPOSIT_MORPHO_AAVE_DAI"),
            addresses.mainnet("PCV_DEPOSIT_MORPHO_AAVE_DAI")
        ];

        PCVGuardian pcvGuardian = PCVGuardian(
            addresses.mainnet("PCV_GUARDIAN")
        );

        vm.roll(block.number + 1); /// compound time advance to accrue interest
        vm.warp(block.timestamp + 15); /// euler time advance to accrue interest

        vm.startPrank(addresses.mainnet("GOVERNOR"));

        for (uint256 i = 0; i < addressesToClean.length; i++) {
            if (IPCVDepositV2(addressesToClean[i]).balance() != 0) {
                pcvGuardian.withdrawAllToSafeAddress(addressesToClean[i]);
            }

            // Check only dust left after withdrawals
            assertLt(IPCVDepositV2(addressesToClean[i]).balance(), 1e6);
        }

        vm.stopPrank();

        // sanity checks
        address safeAddress = pcvGuardian.safeAddress();
        assertTrue(safeAddress != address(0));
        require(
            IERC20(addresses.mainnet("DAI")).balanceOf(safeAddress) >
                1_000_000 * 1e18,
            "Low DAI"
        ); // >1M DAI
        require(
            IERC20(addresses.mainnet("USDC")).balanceOf(safeAddress) >
                10_000 * 1e6,
            "Low USDC"
        ); // >10k USDC

        vm.revertTo(postProposalsSnapshot); // undo withdrawals
    }
}
