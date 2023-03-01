// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {SystemEntry} from "@voltprotocol/entry/SystemEntry.sol";
import {IPCVDepositV2} from "@voltprotocol/pcv/IPCVDepositV2.sol";
import {EulerPCVDeposit} from "@voltprotocol/pcv/euler/EulerPCVDeposit.sol";
import {PostProposalCheck} from "@test/integration/post-proposal-checks/PostProposalCheck.sol";

contract IntegrationTestEulerPCVDeposit is PostProposalCheck {
    using SafeCast for *;

    uint256 depositAmount = 1_000_000;

    function testCanDepositEuler() public {
        SystemEntry entry = SystemEntry(addresses.mainnet("SYSTEM_ENTRY"));
        EulerPCVDeposit daiDeposit = EulerPCVDeposit(
            addresses.mainnet("PCV_DEPOSIT_EULER_DAI")
        );
        EulerPCVDeposit usdcDeposit = EulerPCVDeposit(
            addresses.mainnet("PCV_DEPOSIT_EULER_USDC")
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

    function testHarvestEuler() public {
        testCanDepositEuler();

        SystemEntry entry = SystemEntry(addresses.mainnet("SYSTEM_ENTRY"));
        EulerPCVDeposit daiDeposit = EulerPCVDeposit(
            addresses.mainnet("PCV_DEPOSIT_EULER_DAI")
        );
        EulerPCVDeposit usdcDeposit = EulerPCVDeposit(
            addresses.mainnet("PCV_DEPOSIT_EULER_USDC")
        );

        entry.harvest(address(daiDeposit));
        entry.harvest(address(usdcDeposit));
    }

    function testAccrueEuler() public {
        testCanDepositEuler();

        SystemEntry entry = SystemEntry(addresses.mainnet("SYSTEM_ENTRY"));
        EulerPCVDeposit daiDeposit = EulerPCVDeposit(
            addresses.mainnet("PCV_DEPOSIT_EULER_DAI")
        );
        EulerPCVDeposit usdcDeposit = EulerPCVDeposit(
            addresses.mainnet("PCV_DEPOSIT_EULER_USDC")
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
}
