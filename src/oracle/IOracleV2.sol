// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

/// @title Generic oracle interface for Volt Protocol
/// @author Volt Protocol
interface IOracleV2 {
    /// @notice Read oracle value and its validity status
    /// @return oracleValue value of the oracle, expressed with 18 decimals
    /// @return oracleValid validity of the oracle
    function read()
        external
        view
        returns (uint256 oracleValue, bool oracleValid);
}
