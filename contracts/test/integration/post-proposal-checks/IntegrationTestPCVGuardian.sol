// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {PostProposalCheck} from "./PostProposalCheck.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";

contract IntegrationTestPCVGuardian is PostProposalCheck {
    function testWithdrawAllToSafeAddress() public {
        PCVGuardian pcvGuardian = PCVGuardian(
            addresses.mainnet("PCV_GUARDIAN")
        );

        vm.startPrank(addresses.mainnet("GOVERNOR"));
        pcvGuardian.withdrawAllToSafeAddress(addresses.mainnet("PSM_DAI"));
        pcvGuardian.withdrawAllToSafeAddress(addresses.mainnet("PSM_USDC"));
        pcvGuardian.withdrawAllToSafeAddress(
            addresses.mainnet("PCV_DEPOSIT_MORPHO_DAI")
        );
        pcvGuardian.withdrawAllToSafeAddress(
            addresses.mainnet("PCV_DEPOSIT_MORPHO_USDC")
        );
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
