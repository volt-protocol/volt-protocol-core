// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {CoreRef} from "../refs/CoreRef.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

/// @title PausableLib
/// @notice PausableLib is a library that can be used to pause and unpause contracts, among other utilities.
/// @dev This library should only be used on contracts that implement CoreRef.
library CoreRefPausableLib {
    function _pause(address _pauseableCoreRefAddress) internal {
        CoreRef(_pauseableCoreRefAddress).pause();
    }

    function _unpause(address _pauseableCoreRefAddress) internal {
        CoreRef(_pauseableCoreRefAddress).unpause();
    }

    function _paused(address _pauseableCoreRefAddres)
        internal
        view
        returns (bool)
    {
        return CoreRef(_pauseableCoreRefAddres).paused();
    }
}
