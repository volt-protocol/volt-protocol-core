// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CoreV2} from "../core/CoreV2.sol";
import {ICoreV2} from "../core/ICoreV2.sol";
import {VoltRoles} from "./../core/VoltRoles.sol";
import {ICoreRefV2} from "./ICoreRefV2.sol";
import {IPCVOracle} from "./../oracle/IPCVOracle.sol";
import {IVolt, IVoltBurn} from "./../volt/IVolt.sol";
import {IGlobalReentrancyLock} from "./../core/IGlobalReentrancyLock.sol";
import {IGlobalRateLimitedMinter} from "../limiter/IGlobalRateLimitedMinter.sol";
import {IGlobalSystemExitRateLimiter} from "../limiter/IGlobalSystemExitRateLimiter.sol";

/// @title A Reference to Core
/// @author Volt Protocol
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
    /// 3. call core and unlock the lock back to starting level
    modifier globalLock(uint8 level) {
        IGlobalReentrancyLock lock = globalReentrancyLock();
        lock.lock(level);
        _;
        lock.unlock(level - 1);
    }

    /// @notice modifier to restrict function acces to a certain lock level
    modifier isGlobalReentrancyLocked(uint8 level) {
        IGlobalReentrancyLock lock = globalReentrancyLock();

        require(lock.lockLevel() == level, "CoreRef: System not at lock level");
        _;
    }

    /// @notice callable only by the Volt Minter
    modifier onlyMinter() {
        require(_core.isMinter(msg.sender), "CoreRef: Caller is not a minter");
        _;
    }

    /// @notice callable only by the PCV Controller
    modifier onlyPCVController() {
        require(
            _core.isPCVController(msg.sender),
            "CoreRef: Caller is not a PCV controller"
        );
        _;
    }

    /// @notice callable only by governor
    modifier onlyGovernor() {
        require(
            _core.isGovernor(msg.sender),
            "CoreRef: Caller is not a governor"
        );
        _;
    }

    /// @notice callable only by guardian or governor
    modifier onlyGuardianOrGovernor() {
        require(
            _core.isGovernor(msg.sender) || _core.isGuardian(msg.sender),
            "CoreRef: Caller is not a guardian or governor"
        );
        _;
    }

    /// @notice Named onlyVoltRole to prevent collision with OZ onlyRole modifier
    modifier onlyVoltRole(bytes32 role) {
        require(_core.hasRole(role, msg.sender), "UNAUTHORIZED");
        _;
    }

    /// @notice Modifiers to allow any combination of two roles
    modifier hasAnyOfTwoRoles(bytes32 role1, bytes32 role2) {
        require(
            _core.hasRole(role1, msg.sender) ||
                _core.hasRole(role2, msg.sender),
            "UNAUTHORIZED"
        );
        _;
    }

    /// @notice Modifier to allow any combination of three roles
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

    /// @notice address of the Core contract referenced
    /// @return ICore implementation address
    function core() public view override returns (ICoreV2) {
        return ICoreV2(address(_core));
    }

    /// @notice address of the Volt contract referenced by Core
    /// @return IVoltBurn implementation address
    function volt() internal view returns (IVoltBurn) {
        return IVoltBurn(address(_core.volt()));
    }

    /// @notice address of the Vcon contract referenced by Core
    /// @return IERC20 implementation address
    function vcon() internal view returns (IERC20) {
        return _core.vcon();
    }

    /// @notice address of the PCVOracle contract referenced by Core
    /// @return IPCVOracle implementation address
    function pcvOracle() internal view returns (IPCVOracle) {
        return _core.pcvOracle();
    }

    /// @notice address of the GlobalRateLimitedMinter contract referenced by Core
    /// @return IGlobalRateLimitedMinter implementation address
    function globalRateLimitedMinter()
        internal
        view
        returns (IGlobalRateLimitedMinter)
    {
        return _core.globalRateLimitedMinter();
    }

    /// @notice address of the GlobalSystemExitRateLimiter contract referenced by Core
    /// @return IGlobalSystemExitRateLimiter implementation address
    function globalSystemExitRateLimiter()
        internal
        view
        returns (IGlobalSystemExitRateLimiter)
    {
        return _core.globalSystemExitRateLimiter();
    }

    /// @notice address of the Global Reentrancy Lock contract reference
    /// @return address as type IGlobalReentrancyLock
    function globalReentrancyLock()
        internal
        view
        returns (IGlobalReentrancyLock)
    {
        return _core.globalReentrancyLock();
    }

    /// ------------------------------------------------------
    /// ----------- Governor or Guardian Only API ------------
    /// ------------------------------------------------------

    /// @notice set pausable methods to paused
    function pause() public override onlyGuardianOrGovernor {
        _pause();
    }

    /// @notice set pausable methods to unpaused
    function unpause() public override onlyGuardianOrGovernor {
        _unpause();
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
        /// @notice target address to call
        address target;
        /// @notice amount of eth to send with the call
        uint256 value;
        /// @notice payload to send to target
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
    /// if pcv oracle is not set to address 0, and updates the balance
    function _pcvOracleHook(int256 deltaBalance, int256 deltaProfit) internal {
        IPCVOracle _pcvOracle = pcvOracle();
        if (address(_pcvOracle) != address(0)) {
            /// if any amount of PCV is withdrawn and no gains, delta is negative
            _pcvOracle.updateBalance(deltaBalance, deltaProfit);
        }
    }
}
