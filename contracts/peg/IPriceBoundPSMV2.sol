pragma solidity =0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Decimal} from "../external/Decimal.sol";
import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {PCVDeposit} from "../pcv/PCVDeposit.sol";
import {OracleRefV2} from "../refs/OracleRefV2.sol";

interface IPriceBoundPSMV2 {
    /// @notice event emitted upon a redemption
    event Redeem(address to, uint256 amountVoltIn, uint256 amountAssetOut);

    /// @notice event emitted when volt gets minted
    event Mint(address to, uint256 amountIn, uint256 amountVoltOut);

    /// @notice get volt
    /// @param to address that receives the Volt
    /// @param amountAssetIn amount of underlying token to transfer in
    /// @param minAmountVoltOut minimum amount of Volt received for transaction to succeed
    function mint(
        address to,
        uint256 amountAssetIn,
        uint256 minAmountVoltOut
    ) external returns (uint256 amountVoltOut);

    /// @notice dispose of volt
    /// @param to address that receives the Volt
    /// @param amountVoltIn amount of volt to burn
    /// @param minAmountUnderlyingOut minimum amount of underlying received for transaction to succeed
    function redeem(
        address to,
        uint256 amountVoltIn,
        uint256 minAmountUnderlyingOut
    ) external returns (uint256 amountOut);
}
