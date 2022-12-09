// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IOracleV2} from "../oracle/IOracleV2.sol";
import {CoreRefV2} from "./CoreRefV2.sol";
import {IOracleRefV2} from "./IOracleRefV2.sol";

/// @title Reference to an Oracle
/// @author Volt Protocol
/// @notice defines some utilities around interacting with the referenced oracle
abstract contract OracleRefV2 is IOracleRefV2, CoreRefV2 {
    /// @notice the oracle reference by the contract
    IOracleV2 public override oracle;

    /// @notice the backup oracle reference by the contract
    IOracleV2 public override backupOracle;

    /// @notice number of decimals to scale oracle price by, i.e. multiplying by 10^(decimalsNormalizer)
    int256 public immutable override decimalsNormalizer;

    /// @notice bool flag to invert price read from oracle
    bool public immutable override doInvert;

    /// @notice OracleRef constructor
    /// @param _core Volt Core to reference
    /// @param _oracle oracle to reference
    /// @param _backupOracle backup oracle to reference
    /// @param _decimalsNormalizer number of decimals to normalize the oracle feed if necessary
    /// @param _doInvert invert the oracle price if this flag is on
    constructor(
        address _core,
        address _oracle,
        address _backupOracle,
        int256 _decimalsNormalizer,
        bool _doInvert
    ) CoreRefV2(_core) {
        doInvert = _doInvert;
        decimalsNormalizer = _decimalsNormalizer;
        _setOracle(_oracle);
        _setBackupOracle(_backupOracle);
    }

    /// @notice sets the referenced oracle
    /// @param newOracle the new oracle to reference
    function setOracle(address newOracle) external override onlyGovernor {
        _setOracle(newOracle);
    }

    /// @notice sets the referenced backup oracle
    /// @param newBackupOracle the new backup oracle to reference
    function setBackupOracle(
        address newBackupOracle
    ) external override onlyGovernor {
        _setBackupOracle(newBackupOracle);
    }

    /// @notice return the value of the referenced oracle
    function readOracle() public view override returns (uint256) {
        (uint256 value, bool valid) = oracle.read();
        if (!valid && address(backupOracle) != address(0)) {
            (value, valid) = backupOracle.read();
        }
        require(valid, "OracleRefV2: oracle invalid");

        // Invert the oracle price if necessary
        if (doInvert) {
            value = 1e36 / value;
        }

        // Scale the oracle price by token decimals delta if necessary
        uint256 scalingFactor;
        if (decimalsNormalizer < 0) {
            scalingFactor = 10 ** uint256(-decimalsNormalizer);
            value = value / scalingFactor;
        } else {
            scalingFactor = 10 ** uint256(decimalsNormalizer);
            value = value * scalingFactor;
        }

        return value;
    }

    /// @notice returns inverse of normal value. Used in NonCustodial PSM
    /// to normalize decimals to properly deplete the buffer in the
    /// Global System Exit Rate Limiter
    function getExitValue(uint256 amount) public view returns (uint256) {
        uint256 scalingFactor;
        if (decimalsNormalizer == 0) {
            return amount;
        }
        if (decimalsNormalizer < 0) {
            scalingFactor = 10 ** uint256(-decimalsNormalizer);
            return amount * scalingFactor;
        } else {
            scalingFactor = 10 ** uint256(decimalsNormalizer);
            return amount / scalingFactor;
        }
    }

    function _setOracle(address newOracle) private {
        require(newOracle != address(0), "OracleRefV2: zero address");
        address oldOracle = address(oracle);
        oracle = IOracleV2(newOracle);
        emit OracleUpdate(oldOracle, newOracle);
    }

    /// Supports zero address if no backup
    function _setBackupOracle(address newBackupOracle) private {
        address oldBackupOracle = address(backupOracle);
        backupOracle = IOracleV2(newBackupOracle);
        emit BackupOracleUpdate(oldBackupOracle, newBackupOracle);
    }
}
