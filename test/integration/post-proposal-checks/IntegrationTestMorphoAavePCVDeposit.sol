// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {console} from "@forge-std/console.sol";
import {PCVGuardian} from "@voltprotocol/pcv/PCVGuardian.sol";
import {SystemEntry} from "@voltprotocol/entry/SystemEntry.sol";
import {IPCVDepositV2} from "@voltprotocol/pcv/IPCVDepositV2.sol";
import {PostProposalCheck} from "@test/integration/post-proposal-checks/PostProposalCheck.sol";
import {MorphoAavePCVDeposit} from "@voltprotocol/pcv/morpho/MorphoAavePCVDeposit.sol";

contract IntegrationTestMorphoAavePCVDeposit is PostProposalCheck {
    using SafeCast for *;

    uint256 depositAmount = 1_000_000;

    function testCanDepositAave() public {
        SystemEntry entry = SystemEntry(addresses.mainnet("SYSTEM_ENTRY"));
        MorphoAavePCVDeposit daiDeposit = MorphoAavePCVDeposit(
            addresses.mainnet("PCV_DEPOSIT_MORPHO_AAVE_DAI")
        );
        MorphoAavePCVDeposit usdcDeposit = MorphoAavePCVDeposit(
            addresses.mainnet("PCV_DEPOSIT_MORPHO_AAVE_USDC")
        );

        deal(
            addresses.mainnet("DAI"),
            address(daiDeposit),
            depositAmount * 1e18
        );
        deal(
            addresses.mainnet("USDC"),
            address(usdcDeposit),
            depositAmount * 1e6
        );

        entry.deposit(address(daiDeposit));
        entry.deposit(address(usdcDeposit));

        assertApproxEq(
            daiDeposit.balance().toInt256(),
            (depositAmount * 1e18).toInt256(),
            0
        );
        assertApproxEq(
            usdcDeposit.balance().toInt256(),
            (depositAmount * 1e6).toInt256(),
            0
        );
    }

    /// liquidity mining is over for aave, so harvesting fails
    function testHarvestFailsAave() public {
        testCanDepositAave();

        SystemEntry entry = SystemEntry(addresses.mainnet("SYSTEM_ENTRY"));
        MorphoAavePCVDeposit daiDeposit = MorphoAavePCVDeposit(
            addresses.mainnet("PCV_DEPOSIT_MORPHO_AAVE_DAI")
        );
        MorphoAavePCVDeposit usdcDeposit = MorphoAavePCVDeposit(
            addresses.mainnet("PCV_DEPOSIT_MORPHO_AAVE_USDC")
        );

        vm.expectRevert();
        entry.harvest(address(daiDeposit));

        vm.expectRevert();
        entry.harvest(address(usdcDeposit));
    }

    function testAccrueAave() public {
        testCanDepositAave();

        SystemEntry entry = SystemEntry(addresses.mainnet("SYSTEM_ENTRY"));
        MorphoAavePCVDeposit daiDeposit = MorphoAavePCVDeposit(
            addresses.mainnet("PCV_DEPOSIT_MORPHO_AAVE_DAI")
        );
        MorphoAavePCVDeposit usdcDeposit = MorphoAavePCVDeposit(
            addresses.mainnet("PCV_DEPOSIT_MORPHO_AAVE_USDC")
        );

        uint256 daiBalance = entry.accrue(address(daiDeposit));
        uint256 usdcBalance = entry.accrue(address(usdcDeposit));

        assertApproxEq(
            daiBalance.toInt256(),
            (depositAmount * 1e18).toInt256(),
            0
        );
        assertApproxEq(
            usdcBalance.toInt256(),
            (depositAmount * 1e6).toInt256(),
            0
        );
    }

    function testWithdrawPCVGuardian() public {
        testCanDepositAave();

        PCVGuardian pcvGuardian = PCVGuardian(
            addresses.mainnet("PCV_GUARDIAN")
        );

        address[2] memory addressesToClean = [
            addresses.mainnet("PCV_DEPOSIT_MORPHO_AAVE_DAI"),
            addresses.mainnet("PCV_DEPOSIT_MORPHO_AAVE_USDC")
        ];

        vm.startPrank(addresses.mainnet("GOVERNOR"));
        for (uint256 i = 0; i < addressesToClean.length; i++) {
            pcvGuardian.withdrawAllToSafeAddress(addressesToClean[i]);
            // Check only dust left after withdrawals
            assertLt(IPCVDepositV2(addressesToClean[i]).balance(), 1e6);
        }
        vm.stopPrank();

        // sanity checks
        address safeAddress = pcvGuardian.safeAddress();
        require(safeAddress != address(0), "Safe address is 0 address");
        assertApproxEq(
            IERC20(addresses.mainnet("DAI")).balanceOf(safeAddress).toInt256(),
            (depositAmount * 1e18).toInt256(),
            0
        ); // ~1M DAI
        assertApproxEq(
            IERC20(addresses.mainnet("USDC")).balanceOf(safeAddress).toInt256(),
            (depositAmount * 1e6).toInt256(),
            0
        ); // ~1M USDC
    }
}
