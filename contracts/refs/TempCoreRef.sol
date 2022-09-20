// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {CoreRef} from "./CoreRef.sol";
import {VoltV2} from "../volt/VoltV2.sol";

contract TempCoreRef is CoreRef {
    VoltV2 private immutable _volt;

    constructor(address core, VoltV2 volt) CoreRef(core) {
        _volt = volt;
    }
}
