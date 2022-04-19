// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Vm} from "../unit/utils/Vm.sol";
import {DSTest} from "../unit/utils/DSTest.sol";
import {PSMRouter} from "./../../peg/PSMRouter.sol";
import {INonCustodialPSM} from "./../../peg/NonCustodialPSM.sol";
import {IVolt, Volt} from "../../volt/Volt.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "hardhat/console.sol";

contract IntegrationTestPSMRouter is DSTest {
    INonCustodialPSM private voltPsm =
        INonCustodialPSM(0x8251b0B4e789F07038fE22475621252F4d67ECB7);

    INonCustodialPSM private feiPsm =
        INonCustodialPSM(0x2A188F9EB761F70ECEa083bA6c2A40145078dfc2);

    IVolt private volt = IVolt(0x559eBC30b0E58a45Cc9fF573f77EF1e5eb1b3E18);
    IVolt private fei = IVolt(0x956F47F50A910163D8BF957Cf5846D573E7f87CA);
    IERC20 private dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    Vm public constant vm = Vm(HEVM_ADDRESS);

    function testGetRedeemAmountOut() public {
        uint256 amountVoltIn = 100;

        assertEq(voltPsm.getRedeemAmountOut(amountVoltIn), 101); // the amount of FEI we get back from the VOLT/FEI PSM
        assertEq(feiPsm.getRedeemAmountOut(101), 100); // the amount of DAI we get back from the FEI/DAI PSM
    }

    function testMintAmountOut() public {
        uint256 amountDaiIn = 100;

        assertEq(feiPsm.getMintAmountOut(amountDaiIn), 100); // the amount FEI we get from the FEI/DAI PSM
        assertEq(voltPsm.getMintAmountOut(100), 98); // the amount VOLT we get from VOLT/FAI PSM
    }

    function testGetMaxMintAmountOut() public {
        assertEq(voltPsm.getMaxMintAmountOut(), 9976629603360290327059111);
    }
}
