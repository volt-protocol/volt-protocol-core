// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {CoreRef} from "./CoreRef.sol";
import {ICore} from "../core/ICore.sol";

contract VoltCoreRef is CoreRef {
    /// @notice reference to core contract being used.
    ICore private _core;

    constructor(address coreAddress) CoreRef(coreAddress) {
        _core = ICore(coreAddress);
    }

    /// @notice address of the core contract
    /// @return ICore implementation address
    function core() public view override returns (ICore) {
        return _core;
    }

    /// @notice function to set a new core address
    /// @param coreAddress address of the core contract to point to
    function setCore(address coreAddress) external onlyGovernor {
        _core = ICore(coreAddress);
    }
}
