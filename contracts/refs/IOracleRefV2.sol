// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IOracleV2} from "../oracle/IOracleV2.sol";

/// @title OracleRefV2 interface
/// @author Volt Protocol
interface IOracleRefV2 {
    // ----------- Events -----------

    event OracleUpdate(address indexed oldOracle, address indexed newOracle);

    event BackupOracleUpdate(
        address indexed oldBackupOracle,
        address indexed newBackupOracle
    );

    // ----------- Governor only state changing API -----------

    function setOracle(address newOracle) external;

    function setBackupOracle(address newBackupOracle) external;

    // ----------- Getters -----------

    function oracle() external view returns (IOracleV2);

    function backupOracle() external view returns (IOracleV2);

    function doInvert() external view returns (bool);

    function decimalsNormalizer() external view returns (int256);

    function readOracle() external view returns (uint256);
}
