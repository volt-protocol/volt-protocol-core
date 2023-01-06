// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {PostProposalCheck} from "./PostProposalCheck.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";

// Tests that mint & redeem on all PSMS do not revert.
// Does not make any assumptions about the VOLT rate.
contract IntegrationTestUsePSMs is PostProposalCheck {
    uint256 private constant AMOUNT = 5_000;

    function testMainnetUSDCMintRedeem() public {
        PegStabilityModule psm = PegStabilityModule(
            addresses.mainnet("PSM_USDC")
        );
        IERC20 volt = IERC20(addresses.mainnet("VOLT"));
        IERC20 token = IERC20(addresses.mainnet("USDC"));
        uint256 amountTokens = AMOUNT * 1e6;

        // mock non-zero balance of tokens for user
        deal(address(token), address(this), amountTokens);

        // do mint
        token.approve(address(psm), amountTokens);
        psm.mint(address(this), amountTokens, 0);

        // check received volt
        uint256 receivedVolt = volt.balanceOf(address(this));
        assertTrue(receivedVolt > 0);

        // do redeem
        volt.approve(address(psm), receivedVolt);
        psm.redeem(address(this), receivedVolt, 0);

        // check received tokens (tolerance of 1 wei for round-down)
        assertTrue(token.balanceOf(address(this)) >= amountTokens - 1);
    }

    function testMainnetDAIMintRedeem() public {
        PegStabilityModule psm = PegStabilityModule(
            addresses.mainnet("PSM_DAI")
        );
        IERC20 volt = IERC20(addresses.mainnet("VOLT"));
        IERC20 token = IERC20(addresses.mainnet("DAI"));
        uint256 amountTokens = AMOUNT * 1e18;

        // mock non-zero balance of tokens for user
        deal(address(token), address(this), amountTokens);

        // do mint
        token.approve(address(psm), amountTokens);
        psm.mint(address(this), amountTokens, 0);

        // check received volt
        uint256 receivedVolt = volt.balanceOf(address(this));
        assertTrue(receivedVolt > 0);

        // do redeem
        volt.approve(address(psm), receivedVolt);
        psm.redeem(address(this), receivedVolt, 0);

        // check received tokens (tolerance of 1 wei for round-down)
        assertTrue(token.balanceOf(address(this)) >= amountTokens - 1);
    }
}
