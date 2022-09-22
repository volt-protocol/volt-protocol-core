// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IPCVDepositBalances} from "./IPCVDepositBalances.sol";

/// @title Second iteration of a PCV Deposit interface
/// Allows more granular control of how funds are withdrawn.
/// @author Volt Protocol
interface IPCVDepositV2 is IPCVDepositBalances {
    // ----------- Events -----------
    event Deposit(address indexed _from, uint256 _amount);

    event Withdrawal(
        address indexed _caller,
        address indexed _to,
        uint256 _amount
    );

    event WithdrawERC20(
        address indexed _caller,
        address indexed _token,
        address indexed _to,
        uint256 _amount
    );

    event WithdrawETH(
        address indexed _caller,
        address indexed _to,
        uint256 _amount
    );

    // ----------- View Only Functions -----------

    /// @notice return the address of the yield venue based on the PCV deposit
    function getYieldAddressByIndex(uint256 pcvDepositIndex)
        external
        view
        returns (address);

    /// @notice returns a list of all active yield venues in this PCV Deposit
    function getAllYieldVenues() external view returns (address[] memory);

    /// @notice returns a list of all active yield venues in this PCV Deposit
    function getYieldVenueCount() external view returns (uint256);

    // ----------- State changing api -----------

    /// @notice this version of the PCV Deposit has an index for each deposit, and this index must be specified
    /// as there can be multiple supported venues per deposit
    function deposit(uint256 pcvDepositIndex) external;

    // ----------- PCV Controller only state changing api -----------

    /// @notice function that pulls directly out of the underlying yield venue.
    /// equivalent behavior to function `withdrawActive`
    function withdraw(address to, uint256 amount) external;

    /// @notice function that only pulls idle, non deposited funds.
    /// equivalent behavior to function `withdrawERC20` for the underlying token of this deposit
    function withdrawIdle(address to, uint256 amount) external;

    /// @notice function that pulls directly out of the underlying yield venue.
    function withdrawActive(address to, uint256 amount) external;

    /// @notice function that pulls both idle and active funds out of the underlying yield venue.
    /// First pulls any non deployed funds, then if still more funds need to be sent, sends the remaining
    /// by pulling funds from the underlying venue.
    function withdrawMix(address to, uint256 amount) external;

    function withdrawCompoundV2(address to, uint256 amount) external;

    function withdrawCompoundV3(address to, uint256 amount) external;

    function withdrawAave(address to, uint256 amount) external;

    function withdrawEuler(address to, uint256 amount) external;

    function withdrawMorpho(address to, uint256 amount) external;

    function withdrawERC20(
        address token,
        address to,
        uint256 amount
    ) external;

    function withdrawETH(address payable to, uint256 amount) external;

    function withdrawAllAvailableLiquidity(address to) external;

    /// @notice function to withdraw all available liquidity out of the yield venue and deposit
    function withdrawAllAvailableLiquidityByVenue(address to, uint256 index)
        external;
}
