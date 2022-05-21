// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

/// @notice contract that receives a chainlink price feed and then linearly interpolates that rate over
/// a 28 day period into the VOLT price. Interest is compounded monthly when the rate is updated
/// Specifically built for L2 to allow a deployment that is mid-month
/// @author Elliot Friedman
interface IL2ScalingPriceOracle {
    /// @notice event that is emitted when the owner syncs the oracle price
    event OraclePriceUpdate(uint256 oldPrice, uint256 newPrice);

    /// @notice maximum allowable deviation between current and new oracle price the owner sets
    /// Owner can only adjust the price in either direction a maximum of 1%
    function MAX_OWNER_SYNC_DEVIATION() external view returns (uint256);

    /// @notice function to set the oracle price
    /// @param newOraclePrice the new oracle price to sync the starting price between L1 and L2
    function ownerSyncOraclePrice(uint256 newOraclePrice) external;
}
