pragma solidity ^0.8.4;

import {INonCustodialPSM} from "./INonCustodialPSM.sol";
import {IVolt} from "../volt/IVolt.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPSMRouter {
    // ---------- View-Only API ----------

    /// @notice reference to the PegStabilityModule that this router interacts with VOLT/FEI
    function voltPsm() external returns (INonCustodialPSM);

    /// @notice reference to the PegStabilityModule that this router interacts with FEI/DAI
    function feiPsm() external returns (INonCustodialPSM);

    /// @notice reference to the Volt contract used.
    function volt() external returns (IVolt);

    /// @notice reference to the Volt contract used.
    /// @dev Volt and fei share an interface
    function fei() external returns (IVolt);

    /// @notice reference to the Volt contract used.
    function dai() external returns (IERC20);

    /// @notice calculate the amount of VOLT out for a given `amountIn` of underlying
    function getMintAmountOut(uint256 amountIn)
        external
        view
        returns (uint256 amountVoltOut);

    /// @notice the maximum mint amount out
    function getMaxMintAmountOut() external view returns (uint256);

    /// @notice calculate the amount of underlying out for a given `amountVoltIn` of VOLT
    function getRedeemAmountOut(uint256 amountVoltIn)
        external
        view
        returns (uint256 amountOut);

    // ---------- State-Changing API ----------

    /// @notice Mints VOLT to the given address, with a minimum amount required
    /// First pulls the users DAI into the contract
    /// Then makes a call to the FEI/DAI PSM to convert the DAI to FEI
    /// Then calls the VOLT/FEI PSM to convert the FEI to VOLT
    /// Send the VOLT to the specified recipient
    /// @param to The address to mint VOLT to
    /// @param daiAmountIn The amount of dai sent to the contract
    /// @param minAmountVoltOut The minimum amount of VOLT to mint
    function mint(
        address to,
        uint256 daiAmountIn,
        uint256 minAmountVoltOut
    ) external returns (uint256);

    /// @notice Redeems Volt for Dai
    /// First pull user Volt into this contract
    /// Then call redeem on the PSM to turn the Volt into FEI
    /// Call the FEI/DAI PSM to convert the FEI to DAI
    /// Send the DAI to the specified recipient
    /// @param to the address to receive the DAI
    /// @param amountVoltIn the amount of VOLT to redeem
    /// @param minAmountOut the minimum amount of DAI to receive
    function redeem(
        address to,
        uint256 amountVoltIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut);
}
