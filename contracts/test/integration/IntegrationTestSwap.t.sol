// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Vm} from "../unit/utils/Vm.sol";
import {DSTest} from "../unit/utils/DSTest.sol";
import {StdLib} from "../unit/utils/StdLib.sol";
import {INonCustodialPSM} from "./../../peg/NonCustodialPSM.sol";
import {IVolt, Volt} from "../../volt/Volt.sol";
import {OtcEscrow} from "../../utils/OtcEscrow.sol";
import {GlobalRateLimitedMinter} from "../../utils/GlobalRateLimitedMinter.sol";
import {Core} from "../../core/Core.sol";
import {ERC20CompoundPCVDeposit} from "../../pcv/compound/ERC20CompoundPCVDeposit.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract IntegrationTest is DSTest, StdLib {
    IVolt private volt = IVolt(0x559eBC30b0E58a45Cc9fF573f77EF1e5eb1b3E18);
    IVolt private fei = IVolt(0x956F47F50A910163D8BF957Cf5846D573E7f87CA);
    IVolt private dai = IVolt(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    Core private core = Core(0xEC7AD284f7Ad256b64c6E69b84Eb0F48f42e8196);
    ERC20CompoundPCVDeposit private pcvDeposit =
        ERC20CompoundPCVDeposit(0xFeBDf448C8484834bb399d930d7E1bdC773E23bA);

    /// @notice FEI DAO timelock address
    address public immutable feiDAOTimelock =
        0xd51dbA7a94e1adEa403553A8235C302cEbF41a3c;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    uint256 mintAmount = 10_000_000e18;
    uint256 feiMintAmount = 10_170_000e18;

    address public constant deployer =
        0x25dCffa22EEDbF0A69F6277e24C459108c186ecB;

    OtcEscrow constant escrow =
        OtcEscrow(0xeF152E462B59940616E667E801762dA9F2AF97b9);
    GlobalRateLimitedMinter constant globalRateLimitedMinter =
        GlobalRateLimitedMinter(0x87945f59E008aDc9ed6210a8e061f009d6ace718);

    function setUp() public {
        vm.prank(deployer);
        core.grantMinter(address(this));

        volt.mint(address(escrow), mintAmount);

        vm.startPrank(feiDAOTimelock);

        fei.mint(feiDAOTimelock, feiMintAmount);
        fei.approve(address(escrow), feiMintAmount);

        vm.stopPrank();
    }

    function testSwap() public {
        vm.prank(feiDAOTimelock);

        escrow.swap();

        assertEq(fei.balanceOf(address(pcvDeposit)), feiMintAmount);
        assertEq(volt.balanceOf(feiDAOTimelock), mintAmount);
    }
}
