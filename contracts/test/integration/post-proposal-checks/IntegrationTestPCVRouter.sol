// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {PostProposalCheck} from "./PostProposalCheck.sol";

import {PCVRouter} from "../../../pcv/PCVRouter.sol";
import {IPCVDepositV2} from "../../../pcv/IPCVDepositV2.sol";

contract IntegrationTestPCVRouter is PostProposalCheck {
    uint256 private constant AMOUNT = 5_000;

    // Validate that pcv router can be used to move funds
    // Move 5000 DAI from MorphoCompoundDAI PCVDeposit to
    // 5000 USDC in MorphoCompoundUSDC PCVDeposit.
    function testPcvRouterWithSwap() public {
        PCVRouter pcvRouter = PCVRouter(addresses.mainnet("PCV_ROUTER"));
        IPCVDepositV2 daiDeposit = IPCVDepositV2(
            addresses.mainnet("PCV_DEPOSIT_MORPHO_DAI")
        );
        IPCVDepositV2 usdcDeposit = IPCVDepositV2(
            addresses.mainnet("PCV_DEPOSIT_MORPHO_USDC")
        );
        address pcvMover = addresses.mainnet("GOVERNOR"); // an address with PCV_MOVER role

        // read balances before
        uint256 depositDaiBalanceBefore = daiDeposit.balance();
        uint256 depositUsdcBalanceBefore = usdcDeposit.balance();

        // Swap DAI to USDC
        vm.startPrank(pcvMover);
        pcvRouter.movePCV(
            address(daiDeposit), // source
            address(usdcDeposit), // destination
            addresses.mainnet("PCV_SWAPPER_MAKER"), // swapper
            AMOUNT * 1e18, // amount
            addresses.mainnet("DAI"), // sourceAsset
            addresses.mainnet("USDC") // destinationAsset
        );
        vm.stopPrank();

        uint256 depositDaiBalanceAfter = daiDeposit.balance();
        uint256 depositUsdcBalanceAfter = usdcDeposit.balance();

        // tolerate 0.5% err because morpho withdrawals are not exact
        assertGt(
            depositDaiBalanceBefore - depositDaiBalanceAfter,
            (995 * AMOUNT * 1e18) / 1000
        );
        assertGt(
            depositUsdcBalanceAfter - depositUsdcBalanceBefore,
            ((995 * AMOUNT * 1e18) / 1e12) / 1000
        );

        // Swap USDC to DAI (half of previous amount)
        vm.startPrank(pcvMover); // has PCV_MOVER role
        pcvRouter.movePCV(
            address(usdcDeposit), // source
            address(daiDeposit), // destination
            addresses.mainnet("PCV_SWAPPER_MAKER"), // swapper
            (AMOUNT * 1e18) / 2e12, // amount
            addresses.mainnet("USDC"), // sourceAsset
            addresses.mainnet("DAI") // destinationAsset
        );
        vm.stopPrank();

        uint256 depositDaiBalanceFinal = daiDeposit.balance();
        uint256 depositUsdcBalanceFinal = usdcDeposit.balance();

        // tolerate 0.5% err because morpho withdrawals are not exact
        assertGt(
            depositDaiBalanceFinal - depositDaiBalanceAfter,
            (995 * AMOUNT * 1e18) / 2000
        );
        assertGt(
            depositUsdcBalanceAfter - depositUsdcBalanceFinal,
            ((995 * AMOUNT * 1e18) / 1e12) / 2000
        );
    }
}
