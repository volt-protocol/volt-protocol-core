// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IDSSPSM} from "./../maker/IDSSPSM.sol";
import {IPegStabilityModule} from "../../peg/IPegStabilityModule.sol";
import {CoreRef} from "../../refs/CoreRef.sol";
import {TribeRoles} from "../../core/TribeRoles.sol";
import {Constants} from "../../Constants.sol";
import {PCVDepositV2} from "../PCVDepositV2.sol";

/// @notice This contracts allows for swaps between DAI and USDC
/// by using the Maker DAI-USDC PSM
/// @author Elliot Friedman, k-xo
contract CompoundPCVRouter is CoreRef {
    using SafeERC20 for IERC20;

    /// @notice reference to the Maker DAI-USDC PSM that this router interacts with
    /// @dev points to Makers DssPsm contract
    IDSSPSM public immutable daiPSM;

    /// @notice reference to the Compound PCV deposit for USDC
    PCVDepositV2 public immutable daiPcvDeposit;

    /// @notice reference to the Compound PCV deposit for DAI
    PCVDepositV2 public immutable usdcPcvDeposit;

    /// @notice reference to the DAI contract used.
    /// @dev Router can be redeployed if DAI address changes
    IERC20 public constant DAI =
        IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    /// @notice reference to the USDC contract used.
    IERC20 public constant USDC =
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    /// @notice scaling factor for USDC
    uint256 public constant USDC_SCALING_FACTOR = 1e12;

    /// @param _core reference to the core contract
    /// @param _daiPSM Maker DAO DAI PSM
    /// @param _daiPcvDeposit DAI PCV Deposit in compound
    /// @param _usdcPcvDeposit USDC PCV Deposit in compound
    constructor(
        address _core,
        IDSSPSM _daiPSM,
        PCVDepositV2 _daiPcvDeposit,
        PCVDepositV2 _usdcPcvDeposit
    ) CoreRef(_core) {
        daiPSM = _daiPSM;
        daiPcvDeposit = _daiPcvDeposit;
        usdcPcvDeposit = _usdcPcvDeposit;
    }

    /// @notice Function to swap cUSDC for cDAI
    /// @param amountUsdcIn the amount of USDC sold to the DAI PSM
    function swapUsdcForDai(uint256 amountUsdcIn)
        external
        hasAnyOfThreeRoles(
            TribeRoles.GOVERNOR,
            TribeRoles.PCV_CONTROLLER,
            TribeRoles.COMPOUND_PCV_MOVER
        )
    {
        usdcPcvDeposit.withdraw(address(this), amountUsdcIn); /// pull USDC to router
        USDC.safeApprove(address(daiPSM), amountUsdcIn); /// approve DAI PSM to spend USDC
        daiPSM.buyGem(
            address(daiPcvDeposit),
            amountUsdcIn * USDC_SCALING_FACTOR
        ); /// sell USDC for DAI
        daiPcvDeposit.deposit(); /// deposit into compound
    }

    /// @notice Function to swap cDAI for cUSDC
    /// @param amountDaiIn the amount of DAI sold to the DAI PSM in exchange for USDC
    function swapDaiForUsdc(uint256 amountDaiIn)
        external
        hasAnyOfThreeRoles(
            TribeRoles.GOVERNOR,
            TribeRoles.PCV_CONTROLLER,
            TribeRoles.COMPOUND_PCV_MOVER
        )
    {
        daiPcvDeposit.withdraw(address(this), amountDaiIn); /// pull DAI to router
        DAI.safeApprove(address(daiPSM), amountDaiIn); /// approve DAI PSM to spend DAI
        daiPSM.sellGem(
            address(usdcPcvDeposit),
            amountDaiIn / USDC_SCALING_FACTOR
        ); /// sell DAI for USDC
        usdcPcvDeposit.deposit(); /// deposit into compound
    }
}
