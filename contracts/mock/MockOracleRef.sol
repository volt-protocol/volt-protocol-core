/// // SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {OracleRef} from "../refs/OracleRef.sol";

contract MockOracleRef is OracleRef {
    constructor(
        address _core,
        address _oracle,
        address _backupOracle,
        int256 _decimalsNormalizer,
        bool _doInvert
    )
        OracleRef(_core, _oracle, _backupOracle, _decimalsNormalizer, _doInvert)
    {}
}
