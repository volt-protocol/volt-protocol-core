// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";
import {IPCVDepositV2} from "../../../pcv/IPCVDepositV2.sol";
import {PostProposalCheck} from "./PostProposalCheck.sol";
import {CompoundBadDebtSentinel} from "../../../pcv/compound/CompoundBadDebtSentinel.sol";

contract IntegrationTestCompoundBadDebtSentinel is PostProposalCheck {
    function testBadDebtOverThresholdAllowsSentinelWithdraw() public {
        CompoundBadDebtSentinel badDebtSentinel = CompoundBadDebtSentinel(
            addresses.mainnet("COMPOUND_BAD_DEBT_SENTINEL")
        );
        PCVGuardian pcvGuardian = PCVGuardian(
            addresses.mainnet("PCV_GUARDIAN")
        );
        IPCVDepositV2 daiDeposit = IPCVDepositV2(
            addresses.mainnet("PCV_DEPOSIT_MORPHO_DAI")
        );
        IPCVDepositV2 usdcDeposit = IPCVDepositV2(
            addresses.mainnet("PCV_DEPOSIT_MORPHO_USDC")
        );

        address yearn = 0x342491C093A640c7c2347c4FFA7D8b9cBC84D1EB;

        /// zero cDAI and cUSDC balances to create bad debt
        deal(addresses.mainnet("CUSDC"), yearn, 0);
        deal(addresses.mainnet("CDAI"), yearn, 0);

        address[] memory user = new address[](1);
        user[0] = yearn;

        assertTrue(badDebtSentinel.getTotalBadDebt(user) > 10_000_000e18);

        badDebtSentinel.rescueAllFromCompound(user);

        // sanity checks
        assertTrue(daiDeposit.balance() < 10e18);
        assertTrue(usdcDeposit.balance() < 10e6);

        address safeAddress = pcvGuardian.safeAddress();
        require(safeAddress != address(0), "Safe address is 0 address");

        assertTrue(
            IERC20(addresses.mainnet("DAI")).balanceOf(safeAddress) >
                1_000_000 * 1e18
        );
        assertTrue(
            IERC20(addresses.mainnet("USDC")).balanceOf(safeAddress) >
                10_000 * 1e6
        );
    }

    function testNoBadDebtBlocksSentinelWithdraw() public {
        CompoundBadDebtSentinel badDebtSentinel = CompoundBadDebtSentinel(
            addresses.mainnet("COMPOUND_BAD_DEBT_SENTINEL")
        );
        IPCVDepositV2 daiDeposit = IPCVDepositV2(
            addresses.mainnet("PCV_DEPOSIT_MORPHO_DAI")
        );
        IPCVDepositV2 usdcDeposit = IPCVDepositV2(
            addresses.mainnet("PCV_DEPOSIT_MORPHO_USDC")
        );

        address yearn = 0x342491C093A640c7c2347c4FFA7D8b9cBC84D1EB;

        address[] memory users = new address[](2);
        users[0] = yearn; /// yearn is less than morpho, place it first to order list
        users[1] = addresses.mainnet("MORPHO");

        assertEq(badDebtSentinel.getTotalBadDebt(users), 0);

        uint256 daiBalance = daiDeposit.balance();
        uint256 usdcBalance = usdcDeposit.balance();

        badDebtSentinel.rescueAllFromCompound(users);

        assertEq(daiDeposit.balance(), daiBalance);
        assertEq(usdcDeposit.balance(), usdcBalance);
    }
}
