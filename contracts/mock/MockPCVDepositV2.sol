// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {IPCVDeposit} from "../pcv/IPCVDeposit.sol";

contract MockPCVDepositV2 is IPCVDeposit, CoreRefV2 {
    address public override balanceReportedIn;

    uint256 private resistantBalance;
    uint256 private resistantProtocolOwnedFei;

    constructor(
        address _core,
        address _token,
        uint256 _resistantBalance,
        uint256 _resistantProtocolOwnedFei
    ) CoreRefV2(_core) {
        balanceReportedIn = _token;
        resistantBalance = _resistantBalance;
        resistantProtocolOwnedFei = _resistantProtocolOwnedFei;
    }

    receive() external payable {}

    function set(uint256 _resistantBalance, uint256 _resistantProtocolOwnedFei)
        public
    {
        resistantBalance = _resistantBalance;
        resistantProtocolOwnedFei = _resistantProtocolOwnedFei;
    }

    // gets the resistant token balance and protocol owned fei of this deposit
    function resistantBalanceAndVolt()
        external
        view
        override
        returns (uint256, uint256)
    {
        return (resistantBalance, resistantProtocolOwnedFei);
    }

    function accrue() external override {}

    // IPCVDeposit V1
    function deposit() external override {
        resistantBalance = IERC20(balanceReportedIn).balanceOf(address(this));
    }

    function withdraw(address to, uint256 amount) external override {
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
