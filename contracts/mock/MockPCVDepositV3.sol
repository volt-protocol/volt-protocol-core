// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {IPCVDeposit} from "../pcv/IPCVDeposit.sol";

contract MockPCVDepositV3 is IPCVDeposit, CoreRefV2 {
    address public override balanceReportedIn;

    uint256 private resistantBalance;
    uint256 private resistantProtocolOwnedVolt;

    constructor(address _core, address _token) CoreRefV2(_core) {
        balanceReportedIn = _token;
    }

    receive() external payable {}

    function set(uint256 _resistantBalance, uint256 _resistantProtocolOwnedVolt)
        public
    {
        resistantBalance = _resistantBalance;
        resistantProtocolOwnedVolt = _resistantProtocolOwnedVolt;
    }

    // gets the resistant token balance and protocol owned volt of this deposit
    function resistantBalanceAndVolt()
        external
        view
        override
        returns (uint256, uint256)
    {
        return (resistantBalance, resistantProtocolOwnedVolt);
    }

    function accrue() external override {}

    // IPCVDeposit V1
    function deposit() external override globalLock(2) {
        resistantBalance = IERC20(balanceReportedIn).balanceOf(address(this));
    }

    function withdraw(address to, uint256 amount)
        external
        override
        globalLockLevelTwo
    {
        IERC20(balanceReportedIn).transfer(to, amount);
        resistantBalance = IERC20(balanceReportedIn).balanceOf(address(this));
    }

    function withdrawERC20(
        address token,
        address to,
        uint256 amount
    ) external override {
        IERC20(token).transfer(to, amount);
    }

    function withdrawETH(address payable to, uint256 amount)
        external
        override
        onlyPCVController
    {
        to.transfer(amount);
    }

    function balance() external view override returns (uint256) {
        return IERC20(balanceReportedIn).balanceOf(address(this));
    }
}
