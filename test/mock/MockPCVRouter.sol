// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {PCVRouter} from "@voltprotocol/pcv/PCVRouter.sol";
import {VoltRoles} from "@voltprotocol/core/VoltRoles.sol";

contract MockPCVRouter is PCVRouter {
    constructor(address _core) PCVRouter(_core) {}

    function movePCV(
        address source,
        address destination,
        address swapper,
        uint256 amount,
        address sourceAsset,
        address destinationAsset
    ) external onlyVoltRole(VoltRoles.PCV_MOVER) whenNotPaused globalLock(1) {
        /// validate pcv movement
        /// check underlying assets match up and if not that swapper is provided and valid
        _checkPCVMove(
            source,
            destination,
            swapper,
            sourceAsset,
            destinationAsset
        );

        /// optimistically transfer funds to the specified pcv deposit
        /// swapper validity not checked in this contract as the PCV Router will check this
        _movePCV(
            source,
            destination,
            swapper,
            amount,
            sourceAsset,
            destinationAsset
        );
    }
}
