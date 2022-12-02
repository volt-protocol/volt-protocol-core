// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IOracleV2} from "./IOracleV2.sol";
import {CoreRefV2} from "../refs/CoreRefV2.sol";

/// @notice Oracle that returns a constant price
/// @author eswak
contract ConstantPriceOracle is IOracleV2, CoreRefV2 {
    /// @notice Constant oracle value
    uint256 public value;

    /// @param _core reference to the core smart contract
    constructor(address _core, uint256 _value) CoreRefV2(_core) {
        value = _value;
    }

    /// ------------- Only-Governor API ---------

    /// @notice Set the constant value of the oracle
    function setValue(uint256 newValue) external onlyGovernor {
        value = newValue;
    }

    /// ------------- IOracleV2 API -------------

    /// @notice Read oracle value and its validity status
    function read() external view returns (uint256, bool) {
        return (value, true);
    }
}
