// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity =0.8.13;

/// @notice maple pool interface
interface IPool {
    function balanceOf(address) external view returns (uint256);

    function recognizableLossesOf(address) external view returns (uint256);

    /**
        @dev    Returns the amount of funds that an account has earned in total.
        @dev    accumulativeFundsOf(_owner) = withdrawableFundsOf(_owner) + withdrawnFundsOf(_owner)
                                         = (pointsPerShare * balanceOf(_owner) + pointsCorrection[_owner]) / pointsMultiplier
        @param  _owner The address of a token holder.
        @return The amount of funds that `_owner` has earned in total.
    */
    function accumulativeFundsOf(address _owner)
        external
        view
        returns (uint256);

    function custodyAllowance(address _owner, address _custodian)
        external
        view
        returns (uint256);

    /**
        @dev    Returns the total amount of funds a given address is able to withdraw currently.
        @param  owner Address of FDT holder.
        @return A uint256 representing the available funds for a given account.
    */
    function withdrawableFundsOf(address owner) external view returns (uint256);

    /**
        @dev   Handles Liquidity Providers depositing of Liquidity Asset into the LiquidityLocker, minting PoolFDTs.
        @dev   It emits a `DepositDateUpdated` event.
        @dev   It emits a `BalanceUpdated` event.
        @dev   It emits a `Cooldown` event.
        @param amt Amount of Liquidity Asset to deposit.
    */
    function deposit(uint256 amt) external;

    function increaseCustodyAllowance(address, uint256) external;

    function poolState() external view returns (uint256);

    function claim(address, address) external returns (uint256[7] memory);

    function fundLoan(
        address,
        address,
        uint256
    ) external;

    /**
        @dev Activates the cooldown period to withdraw. It can't be called if the account is not providing liquidity.
        @dev It emits a `Cooldown` event.
    */
    function intendToWithdraw() external;

    /**
        @dev   Handles Liquidity Providers withdrawing of Liquidity Asset from the LiquidityLocker, burning PoolFDTs.
        @dev   It emits two `BalanceUpdated` event.
        @param amt Amount of Liquidity Asset to withdraw.
    */
    function withdraw(uint256 amt) external;

    /**
        @dev Withdraws all available funds for a FDT holder.
    */
    function withdrawFunds() external;

    function liquidityAsset() external view returns (address);

    function liquidityLocker() external view returns (address);

    function stakeAsset() external view returns (address);

    function stakeLocker() external view returns (address);

    function stakingFee() external view returns (uint256);

    function principalOut() external view returns (uint256);

    function liquidityCap() external view returns (uint256);

    function lockupPeriod() external view returns (uint256);

    function depositDate(address) external view returns (uint256);

    function debtLockers(address, address) external view returns (address);

    function withdrawCooldown(address) external view returns (uint256);

    function setLiquidityCap(uint256) external;

    function cancelWithdraw() external;

    function isDepositAllowed(uint256) external view returns (bool);
}
