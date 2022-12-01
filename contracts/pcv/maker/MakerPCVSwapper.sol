// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IDSSPSM} from "./IDSSPSM.sol";
import {IPCVSwapper} from "../IPCVSwapper.sol";
import {CoreRefV2} from "../../refs/CoreRefV2.sol";

/// @notice This contracts allows swaps between DAI and USDC through Maker's DAI PSM.
/// @author eswak
contract MakerPCVSwapper is IPCVSwapper, CoreRefV2 {
    /// @notice reference to the Maker DAI-USDC PSM
    address public constant MAKER_PSM =
        0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A;

    /// @notice reference to the contract used to sell USDC for DAI
    address public constant MAKER_GEM_JOIN =
        0x0A59649758aa4d66E25f08Dd01271e891fe52199;

    /// @notice reference to the DAI contract used.
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    /// @notice reference to the USDC contract used.
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @notice scaling factor for USDC
    uint256 public constant USDC_SCALING_FACTOR = 1e12;

    constructor(address _core) CoreRefV2(_core) {}

    // ----------- IPCVSwapper View API ---------------------

    function canSwap(
        address assetIn,
        address assetOut
    ) external view returns (bool) {
        return
            !paused() &&
            ((assetIn == DAI && assetOut == USDC) ||
                (assetIn == USDC && assetOut == DAI));
    }

    // ----------- IPCVSwapper State-changing API -----------

    function swap(
        address assetIn,
        address assetOut,
        address destination
    ) external whenNotPaused returns (uint256) {
        // swap USDC -> DAI
        if (assetIn == USDC && assetOut == DAI) {
            require(
                IDSSPSM(MAKER_PSM).tin() == 0,
                "MakerPCVSwapper: maker fee not 0"
            );

            uint256 usdcIn = IERC20(USDC).balanceOf(address(this));
            uint256 daiOut = usdcIn * USDC_SCALING_FACTOR;
            IERC20(USDC).approve(MAKER_GEM_JOIN, usdcIn); /// approve DAI PSM to spend USDC
            IDSSPSM(MAKER_PSM).sellGem(destination, usdcIn); /// sell USDC for DAI

            emit Swap(assetIn, assetOut, destination, usdcIn, daiOut);
            return daiOut;
        }
        // swap DAI -> USDC
        else if (assetIn == DAI && assetOut == USDC) {
            require(
                IDSSPSM(MAKER_PSM).tout() == 0,
                "MakerPCVSwapper: maker fee not 0"
            );

            uint256 daiIn = IERC20(DAI).balanceOf(address(this));
            uint256 usdcOut = daiIn / USDC_SCALING_FACTOR;
            IERC20(DAI).approve(MAKER_PSM, daiIn); /// approve DAI PSM to spend DAI
            IDSSPSM(MAKER_PSM).buyGem(destination, usdcOut); /// sell DAI for USDC

            emit Swap(assetIn, assetOut, destination, daiIn, usdcOut);
            return usdcOut;
        }
        // swap unsupported
        else {
            revert("MakerPCVSwapper: unsupported asset");
        }
    }
}
