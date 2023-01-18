// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {PostProposalCheck} from "./PostProposalCheck.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";
import {IPCVDepositV2} from "../../../pcv/IPCVDepositV2.sol";

contract IntegrationTestPCVGuardian is PostProposalCheck {
    function testWithdrawAllToSafeAddress() public {
        PCVGuardian pcvGuardian = PCVGuardian(
            addresses.mainnet("PCV_GUARDIAN")
        );

        vm.startPrank(addresses.mainnet("GOVERNOR"));
        address[4] memory addressesToClean = [
            addresses.mainnet("PSM_DAI"),
            addresses.mainnet("PSM_USDC"),
            addresses.mainnet("PCV_DEPOSIT_MORPHO_DAI"),
            addresses.mainnet("PCV_DEPOSIT_MORPHO_USDC")
        ];
        for (uint256 i = 0; i < addressesToClean.length; i++) {
            pcvGuardian.withdrawAllToSafeAddress(addressesToClean[i]);
            // Check only dust left after withdrawals
            assertLt(IPCVDepositV2(addressesToClean[i]).balance(), 1e6);
        }
        vm.stopPrank();

        // sanity checks
        address safeAddress = pcvGuardian.safeAddress();
        require(safeAddress != address(0), "Safe address is 0 address");
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
