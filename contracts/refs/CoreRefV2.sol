// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IVolt} from "./../volt/IVolt.sol";
import {ICoreV2} from "./../core/ICoreV2.sol";
import {VoltRoles} from "./../core/VoltRoles.sol";
import {ICoreRefV2} from "./ICoreRefV2.sol";
import {IGlobalReentrancyLock} from "./../core/IGlobalReentrancyLock.sol";

/// @title A Reference to Core
/// @author Volt & Fei Protocol
/// @notice defines some modifiers and utilities around interacting with Core
abstract contract CoreRefV2 is ICoreRefV2, Pausable {
    using SafeERC20 for IERC20;

    /// @notice reference to Core
    ICoreV2 private immutable _core;

    /// @notice reference to Volt
    IVolt private immutable _volt;

    /// @notice reference to Vcon
    IERC20 private immutable _vcon;

    constructor(address coreAddress) {
        _core = ICoreV2(coreAddress);

        _volt = ICoreV2(coreAddress).volt();
        _vcon = ICoreV2(coreAddress).vcon();
    }

    /// TODO unit, fuzz, integration and invariant testing
    /// 1. call core and lock the lock
    /// 2. execute the code
    /// 3. call core and unlock the lock
    modifier globalReentrancyLock() {
        IGlobalReentrancyLock(address(_core)).lock();
        _;
        IGlobalReentrancyLock(address(_core)).unlock();
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

    modifier onlyLiquidPCVDeposit() {
        require(
            _core.hasRole(VoltRoles.LIQUID_PCV_DEPOSIT, msg.sender),
            "CoreRef: Caller is not a Liquid PCV Deposit"
        );
        _;
    }

    modifier onlyIlliquidPCVDeposit() {
        require(
            _core.hasRole(VoltRoles.ILLIQUID_PCV_DEPOSIT, msg.sender),
            "CoreRef: Caller is not an Illiquid PCV Deposit"
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

    // Named onlyTribeRole to prevent collision with OZ onlyRole modifier
    modifier onlyTribeRole(bytes32 role) {
        require(_core.hasRole(role, msg.sender), "UNAUTHORIZED");
        _;
    }

    // Named onlyTribeRole to prevent collision with OZ onlyRole modifier
    modifier onlyVoltMinter() {
        require(
            _core.hasRole(VoltRoles.VOLT_MINTER_ROLE, msg.sender),
            "UNAUTHORIZED"
        );
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
        return _core;
    }

    /// @notice address of the Fei contract referenced by Core
    /// @return IFei implementation address
    function volt() public view override returns (IVolt) {
        return _volt;
    }

    /// @notice address of the Tribe contract referenced by Core
    /// @return IERC20 implementation address
    function vcon() public view override returns (IERC20) {
        return _vcon;
    }

    /// @notice volt balance of contract
    /// @return volt amount held
    function voltBalance() public view override returns (uint256) {
        return _volt.balanceOf(address(this));
    }

    /// @notice vcon balance of contract
    /// @return vcon amount held
    function vconBalance() public view override returns (uint256) {
        return _vcon.balanceOf(address(this));
    }

    function _burnVoltHeld() internal {
        _volt.burn(voltBalance());
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
    ) external virtual onlyPCVController {
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

    /// TODO add testing here that both sends and does not send eth

    /// @notice due to inflexibility of current smart contracts,
    /// add this ability to be able to execute arbitrary calldata
    /// against arbitrary addresses.
    /// callable only by governor
    function emergencyAction(Call[] calldata calls)
        external
        payable
        onlyGovernor
        returns (bytes[] memory returnData)
    {
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
}
