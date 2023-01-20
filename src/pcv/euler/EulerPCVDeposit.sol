// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IEToken} from "@voltprotocol/pcv/euler/IEToken.sol";
import {CoreRefV2} from "@voltprotocol/refs/CoreRefV2.sol";
import {PCVDepositV2} from "@voltprotocol/pcv/PCVDepositV2.sol";

/// @notice PCV Deposit for Euler
contract EulerPCVDeposit is PCVDepositV2 {
    using SafeERC20 for IERC20;

    /// @notice euler main contract that receives tokens
    address public immutable eulerMain;

    /// @notice reference to the euler token that represents an asset
    IEToken public immutable eToken;

    /// @notice sub-account id for euler
    uint256 public constant subAccountId = 0;

    /// @notice fetch underlying asset by calling pool and getting liquidity asset
    /// @param _core reference to the Core contract
    /// @param _eToken reference to the euler asset token
    /// @param _eulerMain reference to the euler main address
    constructor(
        address _core,
        address _eToken,
        address _eulerMain,
        address _underlying,
        address _rewardToken
    ) PCVDepositV2(_underlying, _rewardToken) CoreRefV2(_core) {
        eToken = IEToken(_eToken);
        eulerMain = _eulerMain;
        address underlying = IEToken(_eToken).underlyingAsset();

        require(underlying == _underlying, "EulerDeposit: underlying mismatch");
    }

    /// @notice return the amount of funds this contract owns in underlying tokens
    function balance() public view override returns (uint256) {
        return eToken.balanceOfUnderlying(address(this));
    }

    /// @notice deposit PCV into Euler.
    function _supply(uint256 amount) internal override {
        /// approve euler main to spend underlying token
        IERC20(token).approve(eulerMain, amount);
        /// deposit into eToken
        eToken.deposit(subAccountId, amount);
    }

    /// @notice withdraw PCV from Euler, only callable by PCV controller
    /// @param to destination after funds are withdrawn from venue
    /// @param amount of PCV to withdraw from the venue
    function _withdrawAndTransfer(
        uint256 amount,
        address to
    ) internal override {
        eToken.withdraw(subAccountId, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @notice this is a no-op
    /// euler distributes tokens through a merkle drop,
    /// no need for claim functionality
    function _claim() internal pure override returns (uint256) {
        return 0;
    }

    /// @notice this is a no-op
    /// euler automatically gets the most up to date balance of each user
    /// and does not require any poking
    function _accrueUnderlying() internal override {}
}
