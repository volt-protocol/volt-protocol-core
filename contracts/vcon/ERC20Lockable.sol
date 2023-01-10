// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "solmate/tokens/ERC20.sol";

/**
 @title ERC20 Lockable contract
 @author eswak
 @notice an ERC20 extension which allows users to define a locking address.
 When a user's tokens are locked in an address, they can't be transferred
 anywhere else.
 */
abstract contract ERC20Lockable is ERC20 {
    /// @notice thrown when violating the lock logic
    error LockError();

    /// @notice mapping of users to lock address
    mapping(address => address) public lockAddress;

    /// @dev Emitted when a `user` lock their tokens on `lock`.
    event Lock(address indexed user, address indexed lock);

    /// @dev Emitted when a `user` unlock their tokens from `lock`.
    event Unlock(address indexed user, address indexed lock);

    /// @notice set the locking address of an account
    function _setLockAddress(address user, address userLock) internal {
        if (userLock == address(0)) revert LockError(); // cannot lock to address(0)
        if (lockAddress[user] != address(0)) revert LockError(); // already locked

        lockAddress[user] = userLock;

        emit Lock(user, userLock);

        // allow locker to pull user's tokens
        allowance[user][userLock] = type(uint256).max;
        emit Approval(user, userLock, type(uint256).max);
    }

    /// @notice unset the locking address of an account
    function _unsetLockAddress(address user) internal {
        address userLock = lockAddress[user];
        if (userLock == address(0)) revert LockError(); // not locked

        delete lockAddress[user];

        emit Unlock(user, userLock);

        // reset locker's allowance on user's tokens
        allowance[user][userLock] = 0;
        emit Approval(user, userLock, 0);
    }

    /// @notice lock msg.sender's tokens on a locker
    function lock(address locker) external {
        _setLockAddress(msg.sender, locker);
    }

    /// @notice unlock a user that is locking on msg.sender
    function unlock(address user) external {
        if (msg.sender != lockAddress[user]) revert LockError(); // invalid unlocker
        _unsetLockAddress(user);
    }

    /*///////////////////////////////////////////////////////////////
                             ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// NOTE: any "removal" of tokens from a user requires them to be unlocked,
    /// unless the tokens are going to the locking address.
    /// The user also can't remove allowance on the locker address.

    function approve(
        address spender,
        uint256 amount
    ) public virtual override returns (bool) {
        if (spender == lockAddress[msg.sender]) revert LockError(); // cannot update allowance
        return super.approve(spender, amount);
    }

    function _burn(address from, uint256 amount) internal virtual override {
        _checkLockedTransfer(from, address(0));
        super._burn(from, amount);
    }

    function transfer(
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        _checkLockedTransfer(msg.sender, to);
        return super.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        _checkLockedTransfer(from, to);
        return super.transferFrom(from, to, amount);
    }

    function _checkLockedTransfer(address from, address to) internal view {
        address _lockAddress = lockAddress[from];
        if (_lockAddress != address(0) && to != _lockAddress)
            revert LockError(); // tokens locked
    }
}
