//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {Addresses} from "../Addresses.sol";
import {MultisigProposal} from "../proposalTypes/MultisigProposal.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PCVOracle} from "../../../oracle/PCVOracle.sol";
import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";

/*
VIP17 Executes after VIP16 (SystemV2 deploy), all PCV is in the multisig
after the execution of VIP15, so this will send funds to the new system.
*/

contract vip17 is MultisigProposal {
    string public name = "VIP17";

    // TODO: put exact numbers here after execution of VIP15
    uint256 public PCV_USDC = 50_000 * 1e6;
    uint256 public PCV_DAI = 1_500_000 * 1e18;

    // Funds to send to each PSM
    uint256 public constant PSM_LIQUID_RESERVE = 10_000;

    constructor() {
        // We expect a 100% PCV change in the PCV Oracle for this proposal, because
        // before this proposal, PCV oracle has 0 PCV, but after, it will list all
        // the protocol's funds.
        EXPECT_PCV_CHANGE = 1e18;
        // We changed the way oracles are handled in PSMs (value is inverted, and
        // the decimals are handled differently), so skip the PSM oracle test.
        SKIP_PSM_ORACLE_TEST = true;
    }

    function deploy(Addresses addresses) public pure {}

    function afterDeploy(Addresses addresses, address deployer) public pure {}

    function run(Addresses addresses, address /* deployer*/) public {
        _pushMultisigAction(
            addresses.mainnet("USDC"),
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                addresses.mainnet("PSM_USDC"),
                PSM_LIQUID_RESERVE * 1e6
            ),
            "Send Protocol USDC to PSM"
        );

        _pushMultisigAction(
            addresses.mainnet("USDC"),
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                addresses.mainnet("PCV_DEPOSIT_MORPHO_USDC"),
                PCV_USDC - PSM_LIQUID_RESERVE * 1e6
            ),
            "Send Protocol USDC to Morpho-Compound USDC Deposit"
        );

        _pushMultisigAction(
            addresses.mainnet("SYSTEM_ENTRY"),
            abi.encodeWithSignature(
                "deposit(address)",
                addresses.mainnet("PCV_DEPOSIT_MORPHO_USDC")
            ),
            "Deposit USDC"
        );

        _pushMultisigAction(
            addresses.mainnet("DAI"),
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                addresses.mainnet("PSM_DAI"),
                PSM_LIQUID_RESERVE * 1e18
            ),
            "Send Protocol DAI to PSM"
        );

        _pushMultisigAction(
            addresses.mainnet("DAI"),
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                addresses.mainnet("PCV_DEPOSIT_MORPHO_DAI"),
                PCV_DAI - PSM_LIQUID_RESERVE * 1e18
            ),
            "Send Protocol DAI to Morpho-Compound DAI Deposit"
        );

        _pushMultisigAction(
            addresses.mainnet("SYSTEM_ENTRY"),
            abi.encodeWithSignature(
                "deposit(address)",
                addresses.mainnet("PCV_DEPOSIT_MORPHO_DAI")
            ),
            "Deposit DAI"
        );

        _simulateMultisigActions(
            addresses.mainnet("GOVERNOR") // multisigAddress
        );
    }

    function teardown(Addresses addresses, address deployer) public pure {}

    function validate(Addresses addresses, address /* deployer*/) public {
        uint256 expectedPcvUsd = PCV_DAI +
            PCV_USDC *
            1e12 -
            2 *
            PSM_LIQUID_RESERVE *
            1e18;
        (, , uint256 totalPcv) = PCVOracle(addresses.mainnet("PCV_ORACLE"))
            .getTotalPcv();
        // tolerate 1 USD "loss" on migration because morpho accounting is pessimistic
        assertGt(totalPcv, expectedPcvUsd - 1e18);
    }
}
