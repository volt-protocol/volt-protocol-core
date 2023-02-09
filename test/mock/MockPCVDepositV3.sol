// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {CoreRefV2} from "@voltprotocol/refs/CoreRefV2.sol";
import {IPCVDeposit} from "@voltprotocol/pcv/IPCVDeposit.sol";
import {IGlobalReentrancyLock} from "@voltprotocol/core/IGlobalReentrancyLock.sol";

contract MockPCVDepositV3 is IPCVDeposit, CoreRefV2 {
    using SafeCast for *;

    address public override balanceReportedIn;
    bool public checkPCVController = false;

    uint256 private resistantBalance;
    uint256 private resistantProtocolOwnedVolt;

    uint256 public lastRecordedProfit;

    constructor(address _core, address _token) CoreRefV2(_core) {
        balanceReportedIn = _token;
    }

    receive() external payable {}

    function set(
        uint256 _resistantBalance,
        uint256 _resistantProtocolOwnedVolt
    ) public {
        resistantBalance = _resistantBalance;
        resistantProtocolOwnedVolt = _resistantProtocolOwnedVolt;
    }

    function setLastRecordedProfit(uint256 _lastRecordedProfit) public {
        IGlobalReentrancyLock lock = globalReentrancyLock();
        if (address(lock) != address(0)) {
            /// pcv oracle hook requires lock level 2
            lock.lock(1);
            lock.lock(2);
        }

        int256 deltaProfit = _lastRecordedProfit.toInt256() -
            lastRecordedProfit.toInt256();
        lastRecordedProfit = _lastRecordedProfit;
        _pcvOracleHook(0, deltaProfit);

        if (address(lock) != address(0)) {
            lock.unlock(1);
            lock.unlock(0);
        }
    }

    function setCheckPCVController(bool value) public {
        checkPCVController = value;
    }

    // gets the resistant token balance and protocol owned volt of this deposit
    function resistantBalanceAndVolt()
        external
        view
        returns (uint256, uint256)
    {
        return (resistantBalance, resistantProtocolOwnedVolt);
    }

    function harvest() external globalLock(2) {
        // noop
    }

    function accrue() external globalLock(2) returns (uint256) {
        uint256 _balance = balance();
        resistantBalance = _balance;

        _pcvOracleHook(0, 0);

        return _balance;
    }

    // IPCVDeposit V1
    function deposit() external override globalLock(2) {
        int256 startingBalance = resistantBalance.toInt256();
        resistantBalance = IERC20(balanceReportedIn).balanceOf(address(this));
        _pcvOracleHook(
            resistantBalance.toInt256().toInt128() - startingBalance,
            0
        );
    }

    function withdraw(
        address to,
        uint256 amount
    ) external override globalLock(2) {
        if (checkPCVController) {
            // simulate onlyPCVController modifier from CoreRef
            require(
                core().isPCVController(msg.sender),
                "CoreRef: Caller is not a PCV controller"
            );
        }
        IERC20(balanceReportedIn).transfer(to, amount);
        resistantBalance = IERC20(balanceReportedIn).balanceOf(address(this));
        _pcvOracleHook(-(amount.toInt256().toInt128()), 0); /// update balance with delta
    }

    function withdrawERC20(
        address token,
        address to,
        uint256 amount
    ) external override {
        IERC20(token).transfer(to, amount);
    }

    function withdrawETH(
        address payable to,
        uint256 amount
    ) external override onlyPCVController {
        to.transfer(amount);
    }

    function balance() public view override returns (uint256) {
        return IERC20(balanceReportedIn).balanceOf(address(this));
    }
}
