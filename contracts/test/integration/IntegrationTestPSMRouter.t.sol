// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Vm} from "../unit/utils/Vm.sol";
import {DSTest} from "../unit/utils/DSTest.sol";
import {PSMRouter} from "./../../peg/PSMRouter.sol";
import {INonCustodialPSM} from "./../../peg/NonCustodialPSM.sol";
import {IVolt, Volt} from "../../volt/Volt.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface INonCustodialPSMTest is INonCustodialPSM {
    function pause() external;

    function paused() external view returns (bool);

    function unpause() external;
}

contract IntegrationTestPSMRouter is DSTest {
    INonCustodialPSMTest private voltPsm =
        INonCustodialPSMTest(0x8251b0B4e789F07038fE22475621252F4d67ECB7);

    INonCustodialPSM private feiPsm =
        INonCustodialPSM(0x2A188F9EB761F70ECEa083bA6c2A40145078dfc2);

    IVolt private volt = IVolt(0x559eBC30b0E58a45Cc9fF573f77EF1e5eb1b3E18);
    IVolt private fei = IVolt(0x956F47F50A910163D8BF957Cf5846D573E7f87CA);
    IVolt private dai = IVolt(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    PSMRouter private router = new PSMRouter(voltPsm, feiPsm, volt, fei, dai);

    uint256 public constant mintAmount = 1_000_000;

    /// @notice FEI DAO timelock address
    address public immutable feiDAOTimelock =
        0xd51dbA7a94e1adEa403553A8235C302cEbF41a3c;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    function setUp() public {
        vm.prank(0xb148E1e51F207c1C63DeC8C67b3AA5cb22C9Be99); // minter address
        volt.mint(address(this), mintAmount);

        vm.prank(feiDAOTimelock);
        fei.mint(address(this), mintAmount);

        vm.prank(0x9759A6Ac90977b93B58547b4A71c78317f391A28); // dai ward address
        dai.mint(address(this), mintAmount);
    }

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

    function testMint() public {
        if (voltPsm.paused()) {
            vm.prank(0x25dCffa22EEDbF0A69F6277e24C459108c186ecB);
            voltPsm.unpause();
        }

        dai.approve(address(router), mintAmount);
        router.mint(address(this), 98, 100);

        assertEq(volt.balanceOf(address(this)), mintAmount + 98);
    }

    function testRedeem() public {
        if (voltPsm.paused()) {
            vm.prank(0x25dCffa22EEDbF0A69F6277e24C459108c186ecB);
            voltPsm.unpause();
        }

        volt.approve(address(router), mintAmount);
        router.redeem(address(this), 100, 100);

        assertEq(dai.balanceOf(address(this)), mintAmount + 100);
    }

    function testMintFailWithoutApproval() public {
        if (voltPsm.paused()) {
            vm.prank(0x25dCffa22EEDbF0A69F6277e24C459108c186ecB);
            voltPsm.unpause();
        }

        vm.expectRevert(bytes("Dai/insufficient-allowance"));
        router.mint(address(this), 98, 100);
    }

    function testRedeemFailWithoutApproval() public {
        if (voltPsm.paused()) {
            vm.prank(0x25dCffa22EEDbF0A69F6277e24C459108c186ecB);
            voltPsm.unpause();
        }

        vm.expectRevert(bytes("ERC20: transfer amount exceeds allowance"));
        router.redeem(address(this), 98, 100);
    }

    function testMintFailWhenMintOutNotEnough() public {
        if (voltPsm.paused()) {
            vm.prank(0x25dCffa22EEDbF0A69F6277e24C459108c186ecB);
            voltPsm.unpause();
        }

        dai.approve(address(router), mintAmount);

        vm.expectRevert(bytes("PegStabilityModule: Mint not enough out"));
        router.mint(address(this), 100, 98);
    }

    function testRedeemFailWhenRedeemOutNotEnough() public {
        if (voltPsm.paused()) {
            vm.prank(0x25dCffa22EEDbF0A69F6277e24C459108c186ecB);
            voltPsm.unpause();
        }

        volt.approve(address(router), mintAmount);

        vm.expectRevert(bytes("PegStabilityModule: Redeem not enough out"));
        router.redeem(address(this), 98, 100);
    }

    function testMintFailWhenContractPaused() public {
        dai.approve(address(router), mintAmount);
        vm.expectRevert(bytes("Pausable: paused"));

        router.mint(address(this), 98, 100);
    }

    function testRedeemFailWhenContractPaused() public {
        volt.approve(address(router), mintAmount);
        vm.expectRevert(bytes("Pausable: paused"));

        router.redeem(address(this), 98, 100);
    }
}
