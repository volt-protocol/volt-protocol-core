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
    /// TODO add support for arbitrum

    /// @notice all PSM's on mainnet
    address[] private allMainnetPSMs = [
        MainnetAddresses.VOLT_DAI_PSM,
        MainnetAddresses.VOLT_USDC_PSM
    ];

    /// @notice amount of volt to redeem for
    uint256 private amountVoltIn = 10_000e18;

    /// @notice amount of dai to mint volt with
    uint256 private amountDaiIn = 1_000_000e18;

    uint256[] private amountsIn = [1_000_000e18, 1_000_000e6];

    ICore private core = ICore(MainnetAddresses.CORE);
    IERC20 private dai = IERC20(MainnetAddresses.DAI);
    IERC20 private usdc = IERC20(MainnetAddresses.USDC);
    IERC20 private volt = IVolt(MainnetAddresses.VOLT);

    IERC20[] private tokensIn = [dai, usdc];

    function _redeem(PriceBoundPSM psm, IERC20 underlying) private {
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
            endingUserVOLTBalance == startingUserVoltBalance - amountVoltIn,
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
        uint256 amountUnderlyingIn
    ) private {
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

        console.log("successfully verified mint for psm: ", address(psm));
    }

    /// @notice call after governance action to verify redeem values
    function postActionVerifyRedeem(Vm vm) internal {
        for (uint256 i = 0; i < allMainnetPSMs.length; i++) {
            vm.startPrank(MainnetAddresses.GOVERNOR);
            core.grantMinter(MainnetAddresses.GOVERNOR);
            IVolt(address(volt)).mint(address(this), amountVoltIn);
            vm.stopPrank();

            _redeem(PriceBoundPSM(allMainnetPSMs[i]), tokensIn[i]);
        }
    }

    /// @notice call after governance action to verify mint values
    function postActionVerifyMint(Vm vm) internal {
        for (uint256 i = 0; i < allMainnetPSMs.length; i++) {
            /// pull all tokens from psm into this address and use them to purchase VOLT
            uint256 amountIn = tokensIn[i].balanceOf(allMainnetPSMs[i]);
            vm.prank(allMainnetPSMs[i]);
            tokensIn[i].transfer(address(this), amountIn);

            /// figure out how many volt we can purchase
            uint256 psmVoltBalance = volt.balanceOf(allMainnetPSMs[i]);
            uint256 maxAmountIn = PriceBoundPSM(allMainnetPSMs[i])
                .getRedeemAmountOut(psmVoltBalance);

            _mint(
                PriceBoundPSM(allMainnetPSMs[i]),
                tokensIn[i],
                Math.min(maxAmountIn, amountIn)
            );
        }
    }
}
