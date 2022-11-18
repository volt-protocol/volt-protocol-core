pragma solidity 0.8.13;

import "./MockERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IERC4626} from "../pcv/ERC4626/IERC4626.sol";

/// @notice this is a mock implementation of an ERC4626 Vault
///         it features a "lock" system where users can lock shares
///         the lock system simulates some kind of staking or lock a real vault could do
///         example: for Maple, shares could be locked because the underlying assets are lent
/// @dev this implementation does not have the particularities of round up or down when calculating
/// the amount of shares or assets. It might be needed later to be more precise
contract MockERC4626Vault is MockERC20, IERC4626 {
    using SafeMath for uint256;

    MockERC20 private immutable _asset;
    uint8 private immutable _decimals;

    // this mapping tracks the locked shares for each vault users
    // we could imagine that the vault lock shares for some times
    // or that the user could stake some shares to earn more profit
    // this will be simulated by the 'mockLockShares' and 
    // 'mockUnlockShares' functions. Calculations of how much one client can 
    // withdraw will be calculated using totalShares(user) - lockedShares(user)
    mapping(address => uint256) public lockedShares; 


//    __  __               _              _     __                      _    _                    
//   |  \/  |             | |            | |   / _|                    | |  (_)                   
//   | \  / |  ___    ___ | | __ ___   __| |  | |_  _   _  _ __    ___ | |_  _   ___   _ __   ___ 
//   | |\/| | / _ \  / __|| |/ // _ \ / _` |  |  _|| | | || '_ \  / __|| __|| | / _ \ | '_ \ / __|
//   | |  | || (_) || (__ |   <|  __/| (_| |  | |  | |_| || | | || (__ | |_ | || (_) || | | |\__ \
//   |_|  |_| \___/  \___||_|\_\\___| \__,_|  |_|   \__,_||_| |_| \___| \__||_| \___/ |_| |_||___/
//                                                                                               
//                                                                                               
// the following functions are allowing to simulate profit and loss on the vault
// and also some kind of "share lock" where all the value deposited cannot be redeemed instantly

    /// @notice simulate a loss of assets, not linked to withdrawals
    function mockLoseSome(uint256 lossAmount) public {
        _asset.mockBurn(address(this), lossAmount);
    }

    /// @notice simulate a gain of assets, not linked to deposits
    function mockGainSome(uint256 profitAmount) public {
        _asset.mint(address(this), profitAmount);
    }

    /// @notice lock some shares from a user
    function mockLockShares(uint256 lockAmount, address user) public {
        require(lockAmount <= balanceOf(user), "Not enough shares to lock");
        lockedShares[user] += lockAmount;
    }

    /// @notice unlock some shares from a user
    function mockUnlockShares(uint256 unlockAmount, address user) public {
        uint256 currentlyLocked = lockedShares[user];
        if(currentlyLocked > unlockAmount) {
            lockedShares[user] -= unlockAmount;
        } else {
            lockedShares[user] = 0;
        }
        
    }

//   __      __            _  _      _____                    _                                _          _    _               
//   \ \    / /           | || |    |_   _|                  | |                              | |        | |  (_)              
//    \ \  / /__ _  _   _ | || |_     | |   _ __ ___   _ __  | |  ___  _ __ ___    ___  _ __  | |_  __ _ | |_  _   ___   _ __  *
//     \ \/ // _` || | | || || __|    | |  | '_ ` _ \ | '_ \ | | / _ \| '_ ` _ \  / _ \| '_ \ | __|/ _` || __|| | / _ \ | '_ \ 
//      \  /| (_| || |_| || || |_    _| |_ | | | | | || |_) || ||  __/| | | | | ||  __/| | | || |_| (_| || |_ | || (_) || | | |
//       \/  \__,_| \__,_||_| \__|  |_____||_| |_| |_|| .__/ |_| \___||_| |_| |_| \___||_| |_| \__|\__,_| \__||_| \___/ |_| |_|
//                                                   | |                                                                      
//                                                   |_|                                                                      

// * copied from openzeppelin, without the rounding up/down. Might need it later

    /**
     * @dev Set the underlying asset contract. This must be an ERC20-compatible contract (ERC20 or ERC777).
     */
    constructor(MockERC20 asset_) {
        _decimals = super.decimals();
        _asset = asset_;
    }

    /** @dev See {IERC4626-asset}. */
    function asset() public view virtual override returns (address) {
        return address(_asset);
    }

    /** @dev See {IERC4626-totalAssets}. */
    function totalAssets() public view virtual override returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    /** @dev See {IERC4626-convertToShares}. */
    function convertToShares(uint256 assets) public view virtual override returns (uint256) {
        return _convertToShares(assets);
    }

    /** @dev See {IERC4626-convertToAssets}. */
    function convertToAssets(uint256 shares) public view virtual override returns (uint256) {
        return _convertToAssets(shares);
    }

    /** @dev See {IERC4626-maxDeposit}. */
    function maxDeposit(address) public view virtual override returns (uint256) {
        return _isVaultHealthy() ? type(uint256).max : 0;
    }

    /** @dev See {IERC4626-maxMint}. */
    function maxMint(address) public view virtual override returns (uint256) {
        return type(uint256).max;
    }

    /** @dev See {IERC4626-maxWithdraw}. */
    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        return _convertToAssets(balanceOf(owner) - lockedShares[owner]);
    }

    /** @dev See {IERC4626-maxRedeem}. */
    function maxRedeem(address owner) public view virtual override returns (uint256) {
        return balanceOf(owner) - lockedShares[owner];
    }

    /** @dev See {IERC4626-previewDeposit}. */
    function previewDeposit(uint256 assets) public view virtual override returns (uint256) {
        return _convertToShares(assets);
    }

    /** @dev See {IERC4626-previewMint}. */
    function previewMint(uint256 shares) public view virtual override returns (uint256) {
        return _convertToAssets(shares);
    }

    /** @dev See {IERC4626-previewWithdraw}. */
    function previewWithdraw(uint256 assets) public view virtual override returns (uint256) {
        return _convertToShares(assets);
    }

    /** @dev See {IERC4626-previewRedeem}. */
    function previewRedeem(uint256 shares) public view virtual override returns (uint256) {
        return _convertToAssets(shares);
    }

    /** @dev See {IERC4626-deposit}. */
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256) {
        require(assets <= maxDeposit(receiver), "ERC4626: deposit more than max");

        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    /** @dev See {IERC4626-mint}. */
    function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
        require(shares <= maxMint(receiver), "ERC4626: mint more than max");

        uint256 assets = previewMint(shares);
        _deposit(_msgSender(), receiver, assets, shares);

        return assets;
    }

    /** @dev See {IERC4626-withdraw}. */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
        require(assets <= maxWithdraw(owner), "ERC4626: withdraw more than max");

        uint256 shares = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return shares;
    }

    /** @dev See {IERC4626-redeem}. */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
        require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");

        uint256 assets = previewRedeem(shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return assets;
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     *
     * Will revert if assets > 0, totalSupply > 0 and totalAssets = 0. That corresponds to a case where any asset
     * would represent an infinite amount of shares.
     */
    function _convertToShares(uint256 assets) internal view virtual returns (uint256) {
        uint256 supply = totalSupply();
        return
            (assets == 0 || supply == 0)
                ? _initialConvertToShares(assets)
                : assets.mul(supply).div(totalAssets());
    }

    /**
     * @dev Internal conversion function (from assets to shares) to apply when the vault is empty.
     *
     * NOTE: Make sure to keep this function consistent with {_initialConvertToAssets} when overriding it.
     */
    function _initialConvertToShares(
        uint256 assets
    ) internal view virtual returns (uint256 shares) {
        return assets;
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares) internal view virtual returns (uint256) {
        uint256 supply = totalSupply();
        return
            (supply == 0) ? _initialConvertToAssets(shares) : shares.mul(totalAssets()).div(supply);
    }

    /**
     * @dev Internal conversion function (from shares to assets) to apply when the vault is empty.
     *
     * NOTE: Make sure to keep this function consistent with {_initialConvertToShares} when overriding it.
     */
    function _initialConvertToAssets(
        uint256 shares
    ) internal view virtual returns (uint256) {
        return shares;
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual {
        // If _asset is ERC777, `transferFrom` can trigger a reenterancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transferred and before the shares are minted, which is a valid state.
        // slither-disable-next-line reentrancy-no-eth
        SafeERC20.safeTransferFrom(_asset, caller, address(this), assets);
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev Withdraw/redeem common workflow.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // If _asset is ERC777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transferred, which is a valid state.
        _burn(owner, shares);
        SafeERC20.safeTransfer(_asset, receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function _isVaultHealthy() private view returns (bool) {
        return totalAssets() > 0 || totalSupply() == 0;
    }
}