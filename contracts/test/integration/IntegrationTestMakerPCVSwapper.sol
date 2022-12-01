//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "../unit/utils/Vm.sol";
import {CoreV2} from "../../core/CoreV2.sol";
import {DSTest} from "../unit/utils/DSTest.sol";
import {MakerPCVSwapper} from "../../pcv/maker/MakerPCVSwapper.sol";
import {MainnetAddresses} from "./fixtures/MainnetAddresses.sol";
import {TestAddresses as addresses} from "../unit/utils/TestAddresses.sol";
import {getCoreV2} from "./../unit/utils/Fixtures.sol";

contract IntegrationTestMakerPCVSwapper is DSTest {
    Vm public constant vm = Vm(HEVM_ADDRESS);

    CoreV2 private core;
    MakerPCVSwapper private swapper;
    IERC20 private dai = IERC20(MainnetAddresses.DAI);
    IERC20 private usdc = IERC20(MainnetAddresses.USDC);
    uint256 private constant BALANCE = 1_000e18;

    function setUp() public {
        core = getCoreV2();
        swapper = new MakerPCVSwapper(address(core));

        // Get some DAI and USDC for tests
        vm.startPrank(MainnetAddresses.DAI_USDC_USDT_CURVE_POOL);
        dai.transfer(address(this), BALANCE);
        usdc.transfer(address(this), BALANCE / 1e12);
        vm.stopPrank();
    }

    function testSetup() public {
        assertEq(address(swapper.core()), address(core));
    }

    function testCanSwap() public {
        assertEq(swapper.canSwap(address(dai), address(usdc)), true);
        assertEq(swapper.canSwap(address(usdc), address(dai)), true);
        assertEq(swapper.canSwap(address(this), address(dai)), false);
        assertEq(swapper.canSwap(address(dai), address(this)), false);
        assertEq(swapper.canSwap(address(this), address(usdc)), false);
        assertEq(swapper.canSwap(address(usdc), address(this)), false);
        assertEq(swapper.canSwap(address(this), address(this)), false);

        // if paused, canSwap returns false always
        vm.prank(addresses.governorAddress);
        swapper.pause();

        assertEq(swapper.canSwap(address(dai), address(usdc)), false);
        assertEq(swapper.canSwap(address(usdc), address(dai)), false);

        vm.prank(addresses.governorAddress);
        swapper.unpause();

        assertEq(swapper.canSwap(address(dai), address(usdc)), true);
        assertEq(swapper.canSwap(address(usdc), address(dai)), true);
    }

    function testSwapDaiToUsdc() public {
        assertEq(dai.balanceOf(address(this)), BALANCE);
        assertEq(usdc.balanceOf(address(this)), BALANCE / 1e12);

        dai.transfer(address(swapper), BALANCE);
        swapper.swap(address(dai), address(usdc), address(this));

        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(usdc.balanceOf(address(this)), (BALANCE * 2) / 1e12);
    }

    function testSwapUsdcToDai() public {
        assertEq(dai.balanceOf(address(this)), BALANCE);
        assertEq(usdc.balanceOf(address(this)), BALANCE / 1e12);

        usdc.transfer(address(swapper), BALANCE / 1e12);
        swapper.swap(address(usdc), address(dai), address(this));

        assertEq(dai.balanceOf(address(this)), BALANCE * 2);
        assertEq(usdc.balanceOf(address(this)), 0);
    }

    function testSwapRevertsIfPaused() public {
        vm.prank(addresses.governorAddress);
        swapper.pause();

        vm.expectRevert("Pausable: paused");
        swapper.swap(address(dai), address(usdc), address(this));
    }
}
