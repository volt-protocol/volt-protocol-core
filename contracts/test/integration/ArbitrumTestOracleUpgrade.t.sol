// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {Vm} from "./../unit/utils/Vm.sol";
import {Core} from "../../core/Core.sol";
import {vip11} from "./vip/vip11.sol";
import {ICore} from "../../core/ICore.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {Constants} from "../../Constants.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {IPCVDeposit} from "../../pcv/IPCVDeposit.sol";
import {IVolt, Volt} from "../../volt/Volt.sol";
import {PCVGuardian} from "../../pcv/PCVGuardian.sol";
import {MockPCVDepositV2} from "../../mock/MockPCVDepositV2.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {ArbitrumAddresses} from "./fixtures/ArbitrumAddresses.sol";
import {VoltSystemOracle} from "../../oracle/VoltSystemOracle.sol";
import {OraclePassThrough} from "../../oracle/OraclePassThrough.sol";
import {TimelockSimulation} from "./utils/TimelockSimulation.sol";
import {ERC20CompoundPCVDeposit} from "../../pcv/compound/ERC20CompoundPCVDeposit.sol";
import {PriceBoundPSM, PegStabilityModule} from "../../peg/PriceBoundPSM.sol";
import {getCore, getMainnetAddresses, VoltTestAddresses} from "../unit/utils/Fixtures.sol";

import "hardhat/console.sol";

contract ArbitrumTestOracleUpgrade is TimelockSimulation, vip11 {
    using SafeCast for *;
    PriceBoundPSM private psm;
    IVolt private volt = IVolt(MainnetAddresses.VOLT);
    IVolt private fei = IVolt(MainnetAddresses.FEI);
    IVolt private underlyingToken = fei;

    /// @notice prices during test will increase 1% monthly
    int256 public constant monthlyChangeRateBasisPoints = 12;

    /// @notice Oracle Pass Through contract
    OraclePassThrough public oracle =
        OraclePassThrough(ArbitrumAddresses.ORACLE_PASS_THROUGH);

    VoltSystemOracle public newOracle =
        VoltSystemOracle(ArbitrumAddresses.VOLT_SYSTEM_ORACLE_144_BIPS);

    PCVGuardian private immutable arbitrumPCVGuardian =
        PCVGuardian(ArbitrumAddresses.PCV_GUARDIAN);

    uint256 public constant startTime = 1663286400;

    function setUp() public {
        vm.warp(startTime);
    }

    /// @notice PSM inverts price
    function testSetup() public {
        /// ensure price is approximately the same at the start time
        assertApproxEq(
            oracle.getCurrentOraclePrice().toInt256(),
            newOracle.getCurrentOraclePrice().toInt256(),
            0
        );

        simulate(
            getArbitrumProposal(),
            TimelockController(payable(ArbitrumAddresses.TIMELOCK_CONTROLLER)),
            arbitrumPCVGuardian,
            ArbitrumAddresses.GOVERNOR,
            MainnetAddresses.EOA_1,
            vm,
            false
        );

        assertEq(
            address(oracle.scalingPriceOracle()),
            ArbitrumAddresses.VOLT_SYSTEM_ORACLE_144_BIPS
        );
    }

    function testInterpolation() public {
        uint256 startPrice = newOracle.getCurrentOraclePrice();

        vm.warp(block.timestamp + newOracle.TIMEFRAME());

        uint256 expectedEndPrice = (startPrice * 10_012) / 10_000;

        assertEq(expectedEndPrice, newOracle.getCurrentOraclePrice());
    }
}
