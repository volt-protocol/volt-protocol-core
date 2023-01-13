// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {PostProposalCheck} from "./PostProposalCheck.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVolt} from "../../../volt/IVolt.sol";
import {NonCustodialPSM} from "../../../peg/NonCustodialPSM.sol";

// Tests that non-custodial redeem on all PSMS do not revert.
// Assumes VOLT > 1$.
contract IntegrationTestUseNCPSMs is PostProposalCheck {
    uint256 private constant AMOUNT = 5_000;

    // Redeem on non-custodial USDC PSM
    function testMainnetUSDCNCRedeem() public {
        NonCustodialPSM psm = NonCustodialPSM(
            addresses.mainnet("PSM_NONCUSTODIAL_USDC")
        );
        IERC20 token = IERC20(addresses.mainnet("USDC"));
        IVolt volt = IVolt(addresses.mainnet("VOLT"));

        // (MOCK) mint VOLT for the user
        vm.prank(addresses.mainnet("GLOBAL_RATE_LIMITED_MINTER"));
        volt.mint(address(this), AMOUNT * 1e18);

        // do non-custodial redeem
        volt.approve(address(psm), AMOUNT * 1e18);
        psm.redeem(address(this), AMOUNT * 1e18, 0);

        // check received tokens
        assertTrue(token.balanceOf(address(this)) > AMOUNT * 1e6);
    }

    // Redeem on non-custodial DAI PSM
    function testMainnetDAINCRedeem() public {
        NonCustodialPSM psm = NonCustodialPSM(
            addresses.mainnet("PSM_NONCUSTODIAL_DAI")
        );
        IERC20 token = IERC20(addresses.mainnet("DAI"));
        IVolt volt = IVolt(addresses.mainnet("VOLT"));

        // (MOCK) mint VOLT for the user
        vm.prank(addresses.mainnet("GLOBAL_RATE_LIMITED_MINTER"));
        volt.mint(address(this), AMOUNT * 1e18);

        // do non-custodial redeem
        volt.approve(address(psm), AMOUNT * 1e18);
        psm.redeem(address(this), AMOUNT * 1e18, 0);

        // check received tokens
        assertTrue(token.balanceOf(address(this)) > AMOUNT * 1e18);
    }
}
