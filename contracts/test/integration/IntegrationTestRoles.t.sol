// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Vm} from "./../unit/utils/Vm.sol";
import {DSTest} from "./../unit/utils/DSTest.sol";
import {getCore, getAddresses} from "./../unit/utils/Fixtures.sol";
import {MockScalingPriceOracle} from "../../mock/MockScalingPriceOracle.sol";
import {MockL2ScalingPriceOracle} from "../../mock/MockL2ScalingPriceOracle.sol";
import {MockChainlinkToken} from "../../mock/MockChainlinkToken.sol";
import {Decimal} from "./../../external/Decimal.sol";
import {ScalingPriceOracle} from "./../../oracle/ScalingPriceOracle.sol";
import {L2ScalingPriceOracle} from "./../../oracle/L2ScalingPriceOracle.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {TribeRoles} from "../../core/TribeRoles.sol";
import {AllMainnetRoles} from "./utils/AllMainnetRoles.sol";

import {console} from "hardhat/console.sol";

contract IntegrationTestRoles is AllMainnetRoles, DSTest {
    constructor() AllMainnetRoles() {}
}
