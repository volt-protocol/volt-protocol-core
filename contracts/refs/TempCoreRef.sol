// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {CoreRef} from "./CoreRef.sol";
import {IVolt} from "../volt/IVolt.sol";

/// @title TempCoreRef
/// @notice This contract is a reference to the core contract, it is for temporary use
/// as the core contract does not allow for the change of the Volt token being pointed to
/// contracts such as PSM inherit the old CoreRef, as such they only have reference to the old volt token
/// the token migration requires that they reference the new VOLT token so they will be redeployed
/// using this temporary core reference during the token migration, rather than redpeploying core, which
/// is a much heavier lift.
contract TempCoreRef is CoreRef {
    /// @notice reference to the new VOLT token.
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
