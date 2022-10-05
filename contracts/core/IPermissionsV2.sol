// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IPermissionsReadV2} from "./IPermissionsReadV2.sol";

/// @title Permissions interface
/// @author Volt Protocol
interface IPermissionsV2 is IPermissionsReadV2, IAccessControl {
    // ----------- Governor only state changing api -----------

    function createRole(bytes32 role, bytes32 adminRole) external;

    function grantMinter(address minter) external;

    function grantPCVController(address pcvController) external;

    function grantGovernor(address governor) external;

    function grantGuardian(address guardian) external;

    function revokeMinter(address minter) external;

    function revokePCVController(address pcvController) external;

    function revokeGovernor(address governor) external;

    function revokeGuardian(address guardian) external;

    // ----------- Revoker only state changing api -----------

    function revokeOverride(bytes32 role, address account) external;

    // ----------- Getters -----------

    function GUARDIAN_ROLE() external view returns (bytes32);

    function GOVERN_ROLE() external view returns (bytes32);

    function MINTER_ROLE() external view returns (bytes32);

    function PCV_CONTROLLER_ROLE() external view returns (bytes32);
}
