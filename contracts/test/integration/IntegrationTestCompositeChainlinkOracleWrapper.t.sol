// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {Vm} from "./../unit/utils/Vm.sol";
import {Core} from "../../core/Core.sol";
import {ICore} from "../../core/ICore.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {Decimal} from "../../external/Decimal.sol";
import {Constants} from "../../Constants.sol";
import {IPCVDeposit} from "../../pcv/IPCVDeposit.sol";
import {IVolt, Volt} from "../../volt/Volt.sol";
import {PCVGuardian} from "../../pcv/PCVGuardian.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {OraclePassThrough} from "../../oracle/OraclePassThrough.sol";
import {TimelockSimulation} from "./utils/TimelockSimulation.sol";
import {ChainlinkOracleWrapper} from "../../oracle/ChainlinkOracleWrapper.sol";
import {ERC20CompoundPCVDeposit} from "../../pcv/compound/ERC20CompoundPCVDeposit.sol";
import {CompositeChainlinkOracleWrapper} from "../../oracle/CompositeChainlinkOracleWrapper.sol";
import {PriceBoundPSM, PegStabilityModule} from "../../peg/PriceBoundPSM.sol";
import {getCore, getMainnetAddresses, VoltTestAddresses} from "../unit/utils/Fixtures.sol";

contract IntegrationTestCompositeChainlinkOracleWrapper is DSTest {
    using Decimal for Decimal.D256;
    using SafeCast for *;

    PriceBoundPSM private psm;
    ICore private core = ICore(MainnetAddresses.CORE);
    ICore private feiCore = ICore(MainnetAddresses.FEI_CORE);
    IVolt private volt = IVolt(MainnetAddresses.VOLT);
    IVolt private fei = IVolt(MainnetAddresses.FEI);
    IVolt private underlyingToken = fei;

    /// @notice prices during test will increase 1% monthly
    int256 public constant monthlyChangeRateBasisPoints = 12;

    /// @notice Oracle Pass Through contract
    OraclePassThrough public oracle =
        OraclePassThrough(MainnetAddresses.ORACLE_PASS_THROUGH);

    PCVGuardian private immutable mainnetPCVGuardian =
        PCVGuardian(MainnetAddresses.PCV_GUARDIAN);

    CompositeChainlinkOracleWrapper private chainlinkCompositeOracle;
    ChainlinkOracleWrapper private chainlinkOracleWrapper;

    uint256 public constant startTime = 1663286400;

    function setUp() public {
        chainlinkOracleWrapper = new ChainlinkOracleWrapper(
            address(core),
            MainnetAddresses.CHAINLINK_COMP_ORACLE_ADDRESS
        );
        chainlinkCompositeOracle = new CompositeChainlinkOracleWrapper(
            address(core),
            MainnetAddresses.CHAINLINK_COMP_ORACLE_ADDRESS,
            oracle
        );
    }

    function testSetup() public {
        (Decimal.D256 memory voltCompPrice, ) = chainlinkCompositeOracle.read();
        (Decimal.D256 memory usdCompPrice, ) = chainlinkOracleWrapper.read();

        uint256 compPriceInVolt = voltCompPrice.value;
        uint256 compPriceInUsd = usdCompPrice.value;
        uint256 currentOraclePrice = oracle.getCurrentOraclePrice();

        assertApproxEq(
            compPriceInUsd.toInt256(),
            ((currentOraclePrice * compPriceInVolt) / 1e18).toInt256(),
            0
        );
    }
}
