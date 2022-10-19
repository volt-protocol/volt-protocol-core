pragma solidity =0.8.13;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {ArbitrumAddresses} from "../fixtures/ArbitrumAddresses.sol";
import {PriceBoundPSM} from "../../../peg/PriceBoundPSM.sol";
import {Vm} from "./../../unit/utils/Vm.sol";
import {IVolt} from "../../../volt/Volt.sol";
import {ICore} from "../../../core/ICore.sol";

import "hardhat/console.sol";

/// @notice contract to verify that all PSM's are able to mint and redeem
/// after a proposal
contract MintRedeemVerification {
    /// @notice all PSM's on mainnet
    address[] private allMainnetPSMs = [
        MainnetAddresses.VOLT_DAI_PSM,
        MainnetAddresses.VOLT_USDC_PSM
    ];

    address[] private allArbitrumPSMs = [
        ArbitrumAddresses.VOLT_DAI_PSM,
        ArbitrumAddresses.VOLT_USDC_PSM
    ];

    ICore private core = ICore(MainnetAddresses.CORE);
    ICore private arbitrumCore = ICore(ArbitrumAddresses.CORE);
    IERC20 private dai = IERC20(MainnetAddresses.DAI);
    IERC20 private usdc = IERC20(MainnetAddresses.USDC);

    IERC20[] private tokensInMainnet = [dai, usdc];
    IERC20[] private tokensInAbitrum = [
        IERC20(ArbitrumAddresses.DAI),
        IERC20(ArbitrumAddresses.USDC)
    ];

    function _redeem(
        PriceBoundPSM psm,
        IERC20 underlying,
        IERC20 volt,
        uint256 amountVoltIn
    ) private {
        if (psm.paused() || psm.redeemPaused()) {
            return;
        }

        uint256 startingUserUnderlyingBalance = underlying.balanceOf(
            address(this)
        );
        uint256 startingPSMUnderlyingBalance = underlying.balanceOf(
            address(psm)
        );
        uint256 startingUserVoltBalance = volt.balanceOf(address(this));
        uint256 startingPSMVoltBalance = volt.balanceOf(address(psm));

        volt.approve(address(psm), amountVoltIn);

        uint256 minAmountOut = psm.getRedeemAmountOut(amountVoltIn);
        uint256 amountOut = psm.redeem(
            address(this),
            amountVoltIn,
            minAmountOut
        );

        uint256 endingUserVOLTBalance = volt.balanceOf(address(this));
        uint256 endingUserUnderlyingBalance = underlying.balanceOf(
            address(this)
        );
        uint256 endingPSMUnderlyingBalance = underlying.balanceOf(address(psm));
        uint256 endingPSMVoltBalance = volt.balanceOf(address(psm));

        require(
            endingPSMUnderlyingBalance ==
                startingPSMUnderlyingBalance - amountOut,
            "RedeemVerification: a0"
        );
        require(
            endingUserVOLTBalance == (startingUserVoltBalance - amountVoltIn),
            "RedeemVerification: a1"
        );
        require(
            endingUserUnderlyingBalance ==
                startingUserUnderlyingBalance + amountOut,
            "RedeemVerification: a2"
        );
        require(
            endingPSMVoltBalance == startingPSMVoltBalance + amountVoltIn,
            "RedeemVerification: a3"
        );
    }

    function _mint(
        PriceBoundPSM psm,
        IERC20 underlying,
        IERC20 volt,
        uint256 amountUnderlyingIn,
        bool doLogging
    ) private {
        if (psm.paused() || psm.mintPaused()) {
            if (doLogging) {
                console.log(
                    "not verifying psm minting, paused: ",
                    address(psm)
                );
            }
            return;
        }

        uint256 startingUserVoltBalance = volt.balanceOf(address(this));
        uint256 startingUserDaiBalance = underlying.balanceOf(address(this));
        uint256 startingPSMVoltBalance = volt.balanceOf(address(psm));
        uint256 startingPSMDaiBalance = underlying.balanceOf(address(psm));

        underlying.approve(address(psm), amountUnderlyingIn);
        uint256 amountOut = psm.getMintAmountOut(amountUnderlyingIn);
        psm.mint(address(this), amountUnderlyingIn, amountOut);

        uint256 endingUserVoltBalance = volt.balanceOf(address(this));
        uint256 endingUserDaiBalance = underlying.balanceOf(address(this));
        uint256 endingPSMVoltBalance = volt.balanceOf(address(psm));
        uint256 endingPSMDaiBalance = underlying.balanceOf(address(psm));

        require(
            startingPSMVoltBalance - endingPSMVoltBalance == amountOut,
            "MintVerification: a0"
        );
        require(
            endingUserVoltBalance == startingUserVoltBalance + amountOut,
            "MintVerification: a1"
        );
        require(
            endingUserDaiBalance == startingUserDaiBalance - amountUnderlyingIn,
            "MintVerification: a2"
        );
        require(
            endingPSMDaiBalance - startingPSMDaiBalance == amountUnderlyingIn,
            "MintVerification: a3"
        );

        if (doLogging) {
            console.log("successfully verified mint for psm: ", address(psm));
        }
    }

    /// @notice call after governance action to verify redeem values
    function doRedeem(Vm vm) external {
        address[] storage allPSMs = block.chainid == 1
            ? allMainnetPSMs
            : allArbitrumPSMs;
        IERC20[] storage allTokens = block.chainid == 1
            ? tokensInMainnet
            : tokensInAbitrum;
        IERC20 volt = block.chainid == 1
            ? IVolt(MainnetAddresses.VOLT)
            : IVolt(ArbitrumAddresses.VOLT);

        for (uint256 i = 0; i < allPSMs.length; i++) {
            uint256 amountVoltIn;

            if (block.chainid == 1) {
                amountVoltIn = 10_000e18;
                vm.startPrank(MainnetAddresses.GOVERNOR);
                core.grantMinter(MainnetAddresses.GOVERNOR);
                IVolt(address(volt)).mint(address(this), amountVoltIn);
                vm.stopPrank();
            } else {
                amountVoltIn = Math.min(
                    IVolt(ArbitrumAddresses.VOLT).balanceOf(allPSMs[i]),
                    1_000e18
                );
                vm.prank(allPSMs[i]);
                IVolt(ArbitrumAddresses.VOLT).transfer(
                    address(this),
                    amountVoltIn
                );
            }

            _redeem(
                PriceBoundPSM(allPSMs[i]),
                allTokens[i],
                volt,
                amountVoltIn
            );
        }

        revert("successfully redeemed on all PSMs");
    }

    /// @notice call after governance action to verify mint values
    function postActionVerifyRedeem(Vm vm) internal {
        vm.expectRevert("successfully redeemed on all PSMs");
        this.doRedeem(vm);
    }

    function doMint(Vm vm, bool doLogging) external {
        address[] storage allPSMs = block.chainid == 1
            ? allMainnetPSMs
            : allArbitrumPSMs;
        IERC20[] storage allTokens = block.chainid == 1
            ? tokensInMainnet
            : tokensInAbitrum;
        IERC20 volt = block.chainid == 1
            ? IVolt(MainnetAddresses.VOLT)
            : IVolt(ArbitrumAddresses.VOLT);

        for (uint256 i = 0; i < allPSMs.length; i++) {
            /// pull all tokens from psm into this address and use them to purchase VOLT
            uint256 amountIn = allTokens[i].balanceOf(allPSMs[i]);
            vm.prank(allPSMs[i]);
            allTokens[i].transfer(address(this), amountIn);

            /// figure out how many volt we can purchase
            uint256 psmVoltBalance = volt.balanceOf(allPSMs[i]);
            uint256 maxAmountIn = PriceBoundPSM(allPSMs[i]).getRedeemAmountOut(
                psmVoltBalance
            );

            _mint(
                PriceBoundPSM(allPSMs[i]),
                allTokens[i],
                volt,
                Math.min(maxAmountIn, amountIn),
                doLogging
            );
        }

        revert("successfully minted on all PSMs");
    }

    /// @notice call after governance action to verify mint values
    function postActionVerifyMint(Vm vm, bool doLogging) internal {
        vm.expectRevert("successfully minted on all PSMs");
        this.doMint(vm, doLogging);
    }
}
