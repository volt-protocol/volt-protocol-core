// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IGRLM} from "../minter/IGRLM.sol";
import {VoltRoles} from "./../core/VoltRoles.sol";
import {ICoreRefV2} from "./ICoreRefV2.sol";
import {IPCVOracle} from "./../oracle/IPCVOracle.sol";
import {CoreV2, ICoreV2} from "./../core/CoreV2.sol";
import {IVolt, IVoltBurn} from "./../volt/IVolt.sol";
import {IGlobalReentrancyLock} from "./../core/IGlobalReentrancyLock.sol";

/// @title A Reference to Core
/// @author Volt & Fei Protocol
/// @notice defines some modifiers and utilities around interacting with Core
abstract contract CoreRefV2 is ICoreRefV2, Pausable {
    using SafeERC20 for IERC20;

    /// @notice reference to Core
    CoreV2 private _core;

    constructor(address coreAddress) {
        _core = CoreV2(coreAddress);
    }

    /// 1. call core and lock the lock
    /// 2. execute the code
    /// 3. call core and unlock the lock
    modifier globalLock(uint8 level) {
        uint8 startingLevel = _core.lockLevel();
        require(
            startingLevel < level,
            "CoreRef: cannot lock less than current level"
        );
        _core.lock(level);
        _;
        _core.unlock(startingLevel);
    }

    modifier isGlobalReentrancyLocked() {
        require(
            IGlobalReentrancyLock(address(_core)).isLocked(),
            "CoreRef: System not locked"
        );
        _;
    }

    modifier onlyMinter() {
        require(_core.isMinter(msg.sender), "CoreRef: Caller is not a minter");
        _;
    }

    modifier onlyPCVController() {
        require(
            _core.isPCVController(msg.sender),
            "CoreRef: Caller is not a PCV controller"
        );
        _;
    }

    modifier onlyGovernor() {
        require(
            _core.isGovernor(msg.sender),
            "CoreRef: Caller is not a governor"
        );
        _;
    }

    modifier onlyGuardianOrGovernor() {
        require(
            _core.isGovernor(msg.sender) || _core.isGuardian(msg.sender),
            "CoreRef: Caller is not a guardian or governor"
        );
        _;
    }

    /// Named onlyVoltRole to prevent collision with OZ onlyRole modifier
    modifier onlyVoltRole(bytes32 role) {
        require(_core.hasRole(role, msg.sender), "UNAUTHORIZED");
        _;
    }

    // Modifiers to allow any combination of roles
    modifier hasAnyOfTwoRoles(bytes32 role1, bytes32 role2) {
        require(
            _core.hasRole(role1, msg.sender) ||
                _core.hasRole(role2, msg.sender),
            "UNAUTHORIZED"
        );
        _;
    }

    modifier hasAnyOfThreeRoles(
        bytes32 role1,
        bytes32 role2,
        bytes32 role3
    ) {
        require(
            _core.hasRole(role1, msg.sender) ||
                _core.hasRole(role2, msg.sender) ||
                _core.hasRole(role3, msg.sender),
            "UNAUTHORIZED"
        );
        _;
    }

    modifier hasAnyOfFourRoles(
        bytes32 role1,
        bytes32 role2,
        bytes32 role3,
        bytes32 role4
    ) {
        require(
            _core.hasRole(role1, msg.sender) ||
                _core.hasRole(role2, msg.sender) ||
                _core.hasRole(role3, msg.sender) ||
                _core.hasRole(role4, msg.sender),
            "UNAUTHORIZED"
        );
        _;
    }

    modifier hasAnyOfFiveRoles(
        bytes32 role1,
        bytes32 role2,
        bytes32 role3,
        bytes32 role4,
        bytes32 role5
    ) {
        require(
            _core.hasRole(role1, msg.sender) ||
                _core.hasRole(role2, msg.sender) ||
                _core.hasRole(role3, msg.sender) ||
                _core.hasRole(role4, msg.sender) ||
                _core.hasRole(role5, msg.sender),
            "UNAUTHORIZED"
        );
        _;
    }

    /// @notice set pausable methods to paused
    function pause() public override onlyGuardianOrGovernor {
        _pause();
    }

    /// @notice set pausable methods to unpaused
    function unpause() public override onlyGuardianOrGovernor {
        _unpause();
    }

    /// @notice address of the Core contract referenced
    /// @return ICore implementation address
    function core() public view override returns (ICoreV2) {
        return ICoreV2(address(_core));
    }

    /// @notice address of the Volt contract referenced by Core
    /// @return IVoltBurn implementation address
    function volt() public view override returns (IVoltBurn) {
        return IVoltBurn(address(_core.volt()));
    }

    /// @notice address of the Vcon contract referenced by Core
    /// @return IERC20 implementation address
    function vcon() public view override returns (IERC20) {
        return _core.vcon();
    }

    /// @notice address of the PCVOracle contract referenced by Core
    /// @return IPCVOracle implementation address
    function pcvOracle() public view override returns (IPCVOracle) {
        return _core.pcvOracle();
    }

    /// @notice address of the GlobalRateLimitedMinter contract referenced by Core
    /// @return IGRLM implementation address
    function globalRateLimitedMinter() public view override returns (IGRLM) {
        return _core.globalRateLimitedMinter();
    }

    /// @notice volt balance of contract
    /// @return volt amount held
    function voltBalance() public view override returns (uint256) {
        return volt().balanceOf(address(this));
    }

    /// @notice vcon balance of contract
    /// @return vcon amount held
    function vconBalance() public view override returns (uint256) {
        return vcon().balanceOf(address(this));
    }

    /// ------------------------------------------
    /// ----------- Governor Only API ------------
    /// ------------------------------------------

    /// @notice WARNING CALLING THIS FUNCTION CAN POTENTIALLY
    /// BRICK A CONTRACT IF CORE IS SET INCORRECTLY
    /// @notice set new reference to core
    /// only callable by governor
    /// @param newCore to reference
    function setCore(address newCore) external onlyGovernor {
        address oldCore = address(_core);
        _core = CoreV2(newCore);

        emit CoreUpdate(oldCore, newCore);
    }

    /// @notice sweep target token, this shouldn't be needed, however it is a backup
    /// in case a contract holds tokens and isn't a PCV Deposit
    /// @param token to sweep
    /// @param to recipient
    /// @param amount of token to be sent
    function sweep(
        address token,
        address to,
        uint256 amount
    ) external virtual onlyGovernor {
        IERC20(token).safeTransfer(to, amount);
    }

    /// ------------------------------------------
    /// ------------ Emergency Action ------------
    /// ------------------------------------------

    /// inspired by MakerDAO Multicall:
    /// https://github.com/makerdao/multicall/blob/master/src/Multicall.sol

    /// @notice struct to pack calldata and targets for an emergency action
    struct Call {
        address target;
        uint256 value;
        bytes callData;
    }

    /// @notice due to inflexibility of current smart contracts,
    /// add this ability to be able to execute arbitrary calldata
    /// against arbitrary addresses.
    /// callable only by governor
    function emergencyAction(
        Call[] calldata calls
    ) external payable onlyGovernor returns (bytes[] memory returnData) {
        returnData = new bytes[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            address payable target = payable(calls[i].target);
            uint256 value = calls[i].value;
            bytes calldata callData = calls[i].callData;

            (bool success, bytes memory returned) = target.call{value: value}(
                callData
            );
            require(success);
            returnData[i] = returned;
        }
    }

    /// ------------------------------------------
    /// ------- PCV Oracle Helper Methods --------
    /// ------------------------------------------

    /// @notice hook into the pcv oracle, calls into pcv oracle with delta
    /// if pcv oracle is not set to address 0, and updates the liquid balance
    function _liquidPcvOracleHook(int256 delta) internal {
        IPCVOracle _pcvOracle = pcvOracle();
        if (address(_pcvOracle) != address(0)) {
            /// if any amount of PCV is withdrawn and no gains, delta is negative
            _pcvOracle.updateLiquidBalance(delta);
        }
    }

    /// @notice hook into the pcv oracle, calls into pcv oracle with delta
    /// if pcv oracle is not set to address 0, and updates the illiquid balance
    function _illiquidPcvOracleHook(int256 delta) internal {
        IPCVOracle _pcvOracle = pcvOracle();
        if (address(_pcvOracle) != address(0)) {
            /// if any amount of PCV is withdrawn and no gains, delta is negative
            _pcvOracle.updateIlliquidBalance(delta);
        }
    }
}
