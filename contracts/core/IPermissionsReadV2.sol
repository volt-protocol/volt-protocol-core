// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

/// @title Permissions Read interface
/// @author Volt & Fei Protocol
interface IPermissionsReadV2 {
    // ----------- Getters -----------

    function isMinter(address _address) external view returns (bool);

    function isGovernor(address _address) external view returns (bool);

    function isGuardian(address _address) external view returns (bool);

    function isPCVController(address _address) external view returns (bool);

    function isState(address _address) external view returns (bool);
}
