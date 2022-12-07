// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

interface IOldPegStabilityModule {
    function mintPaused() external view returns (bool);

    function redeemPaused() external view returns (bool);
}
