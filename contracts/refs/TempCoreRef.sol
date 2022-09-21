// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {CoreRef} from "./CoreRef.sol";
import {IVolt} from "../volt/IVolt.sol";

contract TempCoreRef is CoreRef {
    IVolt private immutable _volt;

    constructor(address core, IVolt voltToken) CoreRef(core) {
        _volt = voltToken;
    }

    /// @notice address of the Volt contract referenced by Core
    /// @return IVolt implementation address
    function volt() public view virtual override returns (IVolt) {
        return _volt;
    }
}
