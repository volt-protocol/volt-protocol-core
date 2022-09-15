// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {MockPCVDepositV2} from "../../mock/MockPCVDepositV2.sol";
import {IPCVDeposit} from "../../pcv/IPCVDeposit.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {OraclePassThrough} from "../../oracle/OraclePassThrough.sol";
import {ICore} from "../../core/ICore.sol";
import {Core} from "../../core/Core.sol";
import {IVolt, Volt} from "../../volt/Volt.sol";
import {PriceBoundPSM, PegStabilityModule} from "../../peg/PriceBoundPSM.sol";
import {getCore, getMainnetAddresses, VoltTestAddresses} from "../unit/utils/Fixtures.sol";
import {ERC20CompoundPCVDeposit} from "../../pcv/compound/ERC20CompoundPCVDeposit.sol";
import {Vm} from "./../unit/utils/Vm.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";

import {Constants} from "../../Constants.sol";

import "hardhat/console.sol";

contract IntegrationTestOracleUpgrade is DSTest {
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

    uint256 public constant startTime = 1663286400;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    function setUp() public {
        vm.warp(startTime);
    }

    /// @notice PSM inverts price
    function testSetup() public {
        console.log(
            "oracle price at unix timestamp 1663268400: ",
            oracle.getCurrentOraclePrice()
        );
    }
}
