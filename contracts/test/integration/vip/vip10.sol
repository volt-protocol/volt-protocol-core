//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {Vm} from "./../../unit/utils/Vm.sol";
import {Core} from "../../../core/Core.sol";
import {IVIP} from "./IVIP.sol";
import {DSTest} from "./../../unit/utils/DSTest.sol";
import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {ArbitrumAddresses} from "../fixtures/ArbitrumAddresses.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";
import {ITimelockSimulation} from "../utils/ITimelockSimulation.sol";
import {ERC20CompoundPCVDeposit} from "../../../pcv/compound/ERC20CompoundPCVDeposit.sol";

/// Only add DAI and USDC to the allocator as the FEI PSM is permanently paused for both minting
/// and redeeming
contract vip10 is DSTest, IVIP {
    using SafeERC20 for IERC20;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    address private fei = MainnetAddresses.FEI;
    address private core = MainnetAddresses.CORE;

    /// @notice target token balance for the DAI PSM to hold
    uint248 private constant targetBalanceDai = 100_000e18;

    /// @notice target token balance for the USDC PSM to hold
    uint248 private constant targetBalanceUsdc = 100_000e6;

    /// @notice scale up USDC value by 12 decimals in order to account for decimal delta
    /// and properly update the buffer in ERC20Allocator
    int8 private constant usdcDecimalNormalizer = 12;

    ERC20CompoundPCVDeposit private daiDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_DAI_PCV_DEPOSIT);
    ERC20CompoundPCVDeposit private feiDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_FEI_PCV_DEPOSIT);
    ERC20CompoundPCVDeposit private usdcDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT);

    function getMainnetProposal()
        public
        pure
        override
        returns (ITimelockSimulation.action[] memory proposal)
    {
        proposal = new ITimelockSimulation.action[](3);

        // proposal[0].target = MainnetAddresses.ERC20_ALLOCATOR; commented while contract is not deployed
        proposal[0].value = 0;
        proposal[0].arguments = abi.encodeWithSignature(
            "createDeposit(address,address,uint248,int8)",
            MainnetAddresses.VOLT_USDC_PSM,
            MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT,
            targetBalanceUsdc,
            usdcDecimalNormalizer /// 12 decimals of normalization
        );
        proposal[0].description = "Add USDC deposit to the ERC20 Allocator";

        // proposal[1].target = MainnetAddresses.ERC20_ALLOCATOR; commented while contract is not deployed
        proposal[1].value = 0;
        proposal[1].arguments = abi.encodeWithSignature(
            "createDeposit(address,address,uint248,int8)",
            MainnetAddresses.VOLT_DAI_PSM,
            MainnetAddresses.COMPOUND_DAI_PCV_DEPOSIT,
            targetBalanceDai,
            0 /// no decimal normalization
        );
        proposal[1].description = "Add DAI deposit to the ERC20 Allocator";

        proposal[2].target = MainnetAddresses.CORE;
        proposal[2].value = 0;
        proposal[2].arguments = abi.encodeWithSignature(
            "grantPCVController(address)"
            // MainnetAddresses.ERC20_ALLOCATOR  commented while contract is not deployed
        );
        proposal[2]
            .description = "Grant ERC20 Allocator pcv controller role to allow pulling from PCV deposits";
    }

    function mainnetSetup() public override {}

    /// assert erc20 allocator is pcv controller
    /// assert erc20 allocator has compound psm and pcv deposit connected
    /// assert erc20 allocator has dai psm and pcv deposit connected
    function mainnetValidate() public override {}

    /// prevent errors by reverting on arbitrum proposal functions being called on this VIP
    function getArbitrumProposal()
        public
        pure
        override
        returns (ITimelockSimulation.action[] memory)
    {
        revert("no arbitrum proposal");
    }

    function arbitrumSetup() public override {
        revert("no arbitrum proposal");
    }

    function arbitrumValidate() public override {
        revert("no arbitrum proposal");
    }
}
