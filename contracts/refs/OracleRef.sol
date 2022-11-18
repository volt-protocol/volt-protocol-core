// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IOracle} from "../oracle/IOracle.sol";
import {Decimal} from "../external/Decimal.sol";
import {CoreRefV2} from "./CoreRefV2.sol";
import {IOracleRef} from "./IOracleRef.sol";

/// @title Reference to an Oracle
/// @author Volt & Fei Protocol
/// @notice defines some utilities around interacting with the referenced oracle
abstract contract OracleRef is IOracleRef, CoreRefV2 {
    using Decimal for Decimal.D256;
    using SafeCast for int256;

    /// @notice the oracle reference by the contract
    IOracle public override oracle;

    /// @notice the backup oracle reference by the contract
    IOracle public override backupOracle;

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
    function setBackupOracle(address newBackupOracle)
        external
        override
        onlyGovernor
    {
        _setBackupOracle(newBackupOracle);
    }

    /// @notice invert a peg price
    /// @param price the peg price to invert
    /// @return the inverted peg as a Decimal
    /// @dev the inverted peg would be X per FEI
    function invert(Decimal.D256 memory price)
        public
        pure
        override
        returns (Decimal.D256 memory)
    {
        return Decimal.one().div(price);
    }

    /// @notice updates the referenced oracle
    function updateOracle() public override {
        oracle.update();
    }

    /// @notice the peg price of the referenced oracle
    /// @return the peg as a Decimal
    /// @dev the peg is defined as VOLT per X with X being ETH, dollars, etc
    function readOracle() public view override returns (Decimal.D256 memory) {
        (Decimal.D256 memory _peg, bool valid) = oracle.read();
        if (!valid && address(backupOracle) != address(0)) {
            (_peg, valid) = backupOracle.read();
        }
        require(valid, "OracleRef: oracle invalid");

        // Invert the oracle price if necessary
        if (doInvert) {
            _peg = invert(_peg);
        }

        // Scale the oracle price by token decimals delta if necessary
        uint256 scalingFactor;
        if (decimalsNormalizer < 0) {
            scalingFactor = 10**(-1 * decimalsNormalizer).toUint256();
            _peg = _peg.div(scalingFactor);
        } else {
            scalingFactor = 10**decimalsNormalizer.toUint256();
            _peg = _peg.mul(scalingFactor);
        }

        return _peg;
    }

    function _setOracle(address newOracle) private {
        require(newOracle != address(0), "OracleRef: zero address");
        address oldOracle = address(oracle);
        oracle = IOracle(newOracle);
        emit OracleUpdate(oldOracle, newOracle);
    }

    /// Supports zero address if no backup
    function _setBackupOracle(address newBackupOracle) private {
        address oldBackupOracle = address(backupOracle);
        backupOracle = IOracle(newBackupOracle);
        emit BackupOracleUpdate(oldBackupOracle, newBackupOracle);
    }
}
