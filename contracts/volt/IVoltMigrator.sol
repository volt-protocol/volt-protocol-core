// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

interface IVoltMigrator {
    // ----------- Events -----------

    event VoltMigrated(
        address indexed from,
        address indexed to,
        uint256 indexed amount
    );

    // ----------- State changing API -----------

    /// @notice function to exchange old VOLT for new VOLT
    /// @param amount the amount of old VOLT user wishes to exchange
    function exchange(uint256 amount) external;

    /// @notice function to exchange old VOLT for new VOLT
    /// takes the minimum of users old VOLT balance, or the amount
    /// user has approved to the migrator contract & exchanges for new VOLT
    function exchangeAll() external;

    /// @notice function to exchange old VOLT for new VOLT
    /// @param amount the amount of old VOLT user wishes to exchange
    /// @param to address to send the new VOLT to
    function exchangeTo(address to, uint256 amount) external;

    /// @notice function to exchange old VOLT for new VOLT
    /// takes the minimum of users old VOLT balance, or the amount
    /// user has approved to the migrator contract & exchanges for new VOLT
    /// @param to address to send the new VOLT to
    function exchangeAllTo(address to) external;
}
