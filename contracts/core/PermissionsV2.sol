// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {IPermissionsV2} from "./IPermissionsV2.sol";

/// @title Access control module for Core
/// @author Volt Protocol
contract PermissionsV2 is IPermissionsV2, AccessControlEnumerable {
    /// @notice main roles in the Volt system
    bytes32 public constant override MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant override PCV_CONTROLLER_ROLE =
        keccak256("PCV_CONTROLLER_ROLE");
    bytes32 public constant override GOVERN_ROLE = keccak256("GOVERN_ROLE");
    bytes32 public constant override GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant override GLOBAL_LOCKER_ROLE =
        keccak256("GLOBAL_LOCKER_ROLE");
    bytes32 public constant PCV_GUARD_ROLE = keccak256("PCV_GUARD_ROLE");
    bytes32 public constant VOLT_MINTER_ROLE = keccak256("VOLT_MINTER_ROLE");

    constructor() {
        // Appointed as a governor so guardian can have indirect access to revoke ability
        _setupRole(GOVERN_ROLE, address(this));

        _setRoleAdmin(MINTER_ROLE, GOVERN_ROLE);
        _setRoleAdmin(PCV_CONTROLLER_ROLE, GOVERN_ROLE);
        _setRoleAdmin(GOVERN_ROLE, GOVERN_ROLE);
        _setRoleAdmin(GUARDIAN_ROLE, GOVERN_ROLE);
        _setRoleAdmin(GLOBAL_LOCKER_ROLE, GOVERN_ROLE);
        _setRoleAdmin(PCV_GUARD_ROLE, GOVERN_ROLE);
        _setRoleAdmin(VOLT_MINTER_ROLE, GOVERN_ROLE);
    }

    modifier onlyGovernor() {
        require(
            isGovernor(msg.sender),
            "Permissions: Caller is not a governor"
        );
        _;
    }

    modifier onlyGuardian() {
        require(
            isGuardian(msg.sender),
            "Permissions: Caller is not a guardian"
        );
        _;
    }

    /// @notice creates a new role to be maintained
    /// @param role the new role id
    /// @param adminRole the admin role id for `role`
    /// @dev can also be used to update admin of existing role
    function createRole(bytes32 role, bytes32 adminRole)
        external
        override
        onlyGovernor
    {
        _setRoleAdmin(role, adminRole);
    }

    /// @notice grants minter role to address
    /// @param minter new minter
    function grantMinter(address minter) external override onlyGovernor {
        _grantRole(MINTER_ROLE, minter);
    }

    /// @notice grants controller role to address
    /// @param pcvController new controller
    function grantPCVController(address pcvController)
        external
        override
        onlyGovernor
    {
        _grantRole(PCV_CONTROLLER_ROLE, pcvController);
    }

    /// @notice grants governor role to address
    /// @param governor new governor
    function grantGovernor(address governor) external override onlyGovernor {
        _grantRole(GOVERN_ROLE, governor);
    }

    /// @notice grants guardian role to address
    /// @param guardian new guardian
    function grantGuardian(address guardian) external override onlyGovernor {
        _grantRole(GUARDIAN_ROLE, guardian);
    }

    /// @notice grants global locker role to address
    /// @param globalLocker new global locker address
    function grantGlobalLocker(address globalLocker)
        external
        override
        onlyGovernor
    {
        _grantRole(GLOBAL_LOCKER_ROLE, globalLocker);
    }

    /// @notice grants PCV Guard role to address
    /// @param pcvGuard address to add as PCV Guard
    function grantPcvGuard(address pcvGuard) external override onlyGovernor {
        _grantRole(PCV_GUARD_ROLE, pcvGuard);
    }

    /// @notice grants ability to mint Volt through the global rate limited minter
    /// @param rateLimitedMinter address to add as a minter in global rate limited minter
    function grantRateLimitedMinter(address rateLimitedMinter)
        external
        override
        onlyGovernor
    {
        _grantRole(VOLT_MINTER_ROLE, rateLimitedMinter);
    }

    /// @notice revokes minter role from address
    /// @param minter ex minter
    function revokeMinter(address minter) external override onlyGovernor {
        _revokeRole(MINTER_ROLE, minter);
    }

    /// @notice revokes pcvController role from address
    /// @param pcvController ex pcvController
    function revokePCVController(address pcvController)
        external
        override
        onlyGovernor
    {
        _revokeRole(PCV_CONTROLLER_ROLE, pcvController);
    }

    /// @notice revokes governor role from address
    /// @param governor ex governor
    function revokeGovernor(address governor) external override onlyGovernor {
        _revokeRole(GOVERN_ROLE, governor);
    }

    /// @notice revokes guardian role from address
    /// @param guardian ex guardian
    function revokeGuardian(address guardian) external override onlyGovernor {
        _revokeRole(GUARDIAN_ROLE, guardian);
    }

    /// @notice revokes global locker role from address
    /// @param globalLocker ex globalLocker
    function revokeGlobalLocker(address globalLocker)
        external
        override
        onlyGovernor
    {
        _revokeRole(GLOBAL_LOCKER_ROLE, globalLocker);
    }

    /// @notice revokes PCV Guard role from address
    /// @param pcvGuard ex PCV Guard
    function revokePcvGuard(address pcvGuard) external override onlyGovernor {
        _revokeRole(PCV_GUARD_ROLE, pcvGuard);
    }

    /// @notice revokes ability to mint Volt through the global rate limited minter
    /// @param rateLimitedMinter ex minter in global rate limited minter
    function revokeRateLimitedMinter(address rateLimitedMinter)
        external
        override
        onlyGovernor
    {
        _revokeRole(VOLT_MINTER_ROLE, rateLimitedMinter);
    }

    /// @notice revokes a role from address
    /// @param role the role to revoke
    /// @param account the address to revoke the role from
    function revokeOverride(bytes32 role, address account)
        external
        override
        onlyGuardian
    {
        require(
            role != GOVERN_ROLE,
            "Permissions: Guardian cannot revoke governor"
        );

        // External call because this contract is appointed as a governor and has access to revoke
        this.revokeRole(role, account);
    }

    /// @notice checks if address is a minter
    /// @param _address address to check
    /// @return true _address is a minter
    // only virtual for testing mock override
    function isMinter(address _address)
        external
        view
        virtual
        override
        returns (bool)
    {
        return hasRole(MINTER_ROLE, _address);
    }

    /// @notice checks if address is a controller
    /// @param _address address to check
    /// @return true _address is a controller
    // only virtual for testing mock override
    function isPCVController(address _address)
        external
        view
        virtual
        override
        returns (bool)
    {
        return hasRole(PCV_CONTROLLER_ROLE, _address);
    }

    /// @notice checks if address is a governor
    /// @param _address address to check
    /// @return true _address is a governor
    // only virtual for testing mock override
    function isGovernor(address _address)
        public
        view
        virtual
        override
        returns (bool)
    {
        return hasRole(GOVERN_ROLE, _address);
    }

    /// @notice checks if address is a guardian
    /// @param _address address to check
    /// @return true _address is a guardian
    // only virtual for testing mock override
    function isGuardian(address _address)
        public
        view
        virtual
        override
        returns (bool)
    {
        return hasRole(GUARDIAN_ROLE, _address);
    }

    /// @notice checks if address has globalLocker role
    /// @param _address address to check
    /// @return true _address is globalLocker
    function isGlobalLocker(address _address)
        public
        view
        override
        returns (bool)
    {
        return hasRole(GLOBAL_LOCKER_ROLE, _address);
    }

    /// @notice checks if address has PCV Guard role
    /// @param _address address to check
    /// @return true if _address has PCV Guard role
    function isPcvGuard(address _address) public view override returns (bool) {
        return hasRole(PCV_GUARD_ROLE, _address);
    }

    /// @notice checks if address has Volt Minter Role
    /// @param _address address to check
    /// @return true if _address has Volt Minter Role
    function isRateLimitedMinter(address _address)
        public
        view
        override
        returns (bool)
    {
        return hasRole(VOLT_MINTER_ROLE, _address);
    }
}
