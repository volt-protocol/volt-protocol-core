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
import {ERC20Allocator} from "../../../pcv/utils/ERC20Allocator.sol";
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

    uint256 private constant bufferCap = 300_000e18;
    uint256 private constant rateLimitPerSecond = 5.78e18;
    uint256 private constant maxRateLimitPerSecond = 1_000e18;

    /// @notice target token balance for the DAI PSM to hold
    uint248 private constant targetBalanceDai = 100_000e18;

    /// @notice target token balance for the USDC PSM to hold
    uint248 private constant targetBalanceUsdc = 100_000e6;

    /// @notice scale up USDC value by 12 decimals in order to account for decimal delta
    /// and properly update the buffer in ERC20Allocator
    int8 private constant usdcDecimalNormalizer = 12;

    /// @notice no scaling to do on DAI as decimals are 18
    int8 private constant daiDecimalNormalizer = 0;

    ERC20CompoundPCVDeposit private daiDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_DAI_PCV_DEPOSIT);
    ERC20CompoundPCVDeposit private feiDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_FEI_PCV_DEPOSIT);
    ERC20CompoundPCVDeposit private usdcDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT);
    ERC20Allocator private allocator =
        ERC20Allocator(MainnetAddresses.ERC20ALLOCATOR);

    ITimelockSimulation.action[] private proposal;

    constructor() {
        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.ERC20ALLOCATOR,
                arguments: abi.encodeWithSignature(
                    "connectPSM(address,uint248,int8)",
                    MainnetAddresses.VOLT_USDC_PSM,
                    targetBalanceUsdc,
                    usdcDecimalNormalizer /// 12 decimals of normalization
                ),
                description: "Add USDC PSM to the ERC20 Allocator"
            })
        );
        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.ERC20ALLOCATOR,
                arguments: abi.encodeWithSignature(
                    "connectPSM(address,uint248,int8)",
                    MainnetAddresses.VOLT_DAI_PSM,
                    targetBalanceDai,
                    daiDecimalNormalizer
                ),
                description: "Add DAI PSM to the ERC20 Allocator"
            })
        );
        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.ERC20ALLOCATOR,
                arguments: abi.encodeWithSignature(
                    "connectDeposit(address,address)",
                    MainnetAddresses.VOLT_DAI_PSM,
                    MainnetAddresses.COMPOUND_DAI_PCV_DEPOSIT
                ),
                description: "Connect DAI deposit to PSM in ERC20 Allocator"
            })
        );
        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.ERC20ALLOCATOR,
                arguments: abi.encodeWithSignature(
                    "connectDeposit(address,address)",
                    MainnetAddresses.VOLT_USDC_PSM,
                    MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT
                ),
                description: "Connect USDC deposit to PSM in ERC20 Allocator"
            })
        );
        proposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.CORE,
                arguments: abi.encodeWithSignature(
                    "grantPCVController(address)",
                    MainnetAddresses.ERC20ALLOCATOR
                ),
                description: "Grant ERC20 Allocator the PCV Controller Role"
            })
        );
    }

    function getMainnetProposal()
        public
        view
        returns (ITimelockSimulation.action[] memory prop)
    {
        prop = proposal;
    }

    function mainnetSetup() public override {}

    function mainnetValidate() public override {
        assertEq(allocator.buffer(), bufferCap);
        assertEq(allocator.bufferCap(), bufferCap);
        assertEq(allocator.MAX_RATE_LIMIT_PER_SECOND(), maxRateLimitPerSecond);
        assertEq(allocator.rateLimitPerSecond(), rateLimitPerSecond);

        /// assert erc20 allocator has usdc psm and pcv deposit connected
        {
            address psmAddress = allocator.pcvDepositToPSM(address(daiDeposit));
            assertEq(psmAddress, MainnetAddresses.VOLT_DAI_PSM);
        }
        /// assert erc20 allocator has dai psm and pcv deposit connected
        {
            address psmAddress = allocator.pcvDepositToPSM(
                address(usdcDeposit)
            );
            assertEq(psmAddress, MainnetAddresses.VOLT_USDC_PSM);
        }

        /// assert decimal normalization and target balances are correct for both dai and usdc
        {
            (
                address psmToken,
                uint248 psmTargetBalance,
                int8 decimalsNormalizer
            ) = allocator.allPSMs(address(MainnetAddresses.VOLT_USDC_PSM));
            assertEq(psmToken, MainnetAddresses.USDC);
            assertEq(psmTargetBalance, targetBalanceUsdc);
            assertEq(decimalsNormalizer, usdcDecimalNormalizer);
        }
        {
            (
                address psmToken,
                uint248 psmTargetBalance,
                int8 decimalsNormalizer
            ) = allocator.allPSMs(address(MainnetAddresses.VOLT_DAI_PSM));
            assertEq(psmToken, MainnetAddresses.DAI);
            assertEq(psmTargetBalance, targetBalanceDai);
            assertEq(decimalsNormalizer, daiDecimalNormalizer);
        }

        /// assert erc20 allocator is pcv controller
        assertTrue(Core(core).isPCVController(MainnetAddresses.ERC20ALLOCATOR));
    }

    /// prevent errors by reverting on arbitrum proposal functions being called on this VIP
    function getArbitrumProposal()
        public
        pure
        override
        returns (ITimelockSimulation.action[] memory)
    {
        revert("no arbitrum proposal");
    }

    function arbitrumSetup() public pure override {
        revert("no arbitrum proposal");
    }

    function arbitrumValidate() public pure override {
        revert("no arbitrum proposal");
    }
}
