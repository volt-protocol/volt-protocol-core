// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

interface IMarketGovernance {
    /// @notice struct that tracks a PCV movement
    /// @param source pcv deposit to pull funds from
    /// @param destination pcv deposit to send funds
    /// @param swapper address to swap tokens
    /// @param amountPcv to move from src to dest
    struct Rebalance {
        address source;
        address destination;
        address swapper;
        uint256 amountPcv;
    }

    /// ---------- Events ----------

    /// @notice event emitted when a user stakes their VCON
    event VconStaked(
        address indexed user,
        uint256 timestamp,
        uint256 vconAmount
    );

    /// @notice event emitted when a user unstakes their VCON
    event VconUnstaked(
        address indexed user,
        uint256 timestamp,
        uint256 vconAmount
    );

    /// @notice emitted when the router is updated
    event PCVRouterUpdated(
        address indexed oldPcvRouter,
        address indexed newPcvRouter
    );

    /// @notice emitted when profit to vcon ratio is updated
    event ProfitToVconRatioUpdated(
        address indexed venue,
        uint256 oldRatio,
        uint256 newRatio
    );

    /// @notice emitted when a loss is realized
    event LossRealized(
        address indexed venue,
        address indexed user,
        uint256 vconLossAmount
    );

    /// @notice emitted whenever a user stakes
    event Staked(
        address indexed venue,
        address indexed user,
        uint256 vconAmount
    );

    /// @notice emitted whenever a user unstakes
    event Unstaked(
        address indexed venue,
        address indexed user,
        uint256 vconAmount,
        uint256 pcvAmount
    );

    /// @notice emitted whenever a user harvests
    event Harvest(
        address indexed venue,
        address indexed user,
        uint256 vconAmount
    );

    /// @notice emitted when a venue's index is updated via accrue
    event VenueIndexUpdated(
        address indexed venue,
        uint256 indexed timestamp,
        uint256 profitIndex
    );

    /// ---------- Permissionless User PCV Allocation Methods ----------

    /// stake VCON on a venue
    /// @param amountVcon to stake
    /// @param source pcv deposit to pull funds from
    function stake(uint256 amountVcon, address source) external;

    /// @notice this function automatically calculates
    /// the amount of PCV to remove from the source
    /// based on the user's total amount of staked VCON
    /// @param amountVcon to stake
    /// @param source pcv deposit to pull funds from
    /// @param destination pcv deposit to send funds
    /// @param swapper address to swap tokens
    /// @param vconRecipient address to receive VCON tokens
    function unstake(
        uint256 amountVcon,
        address source,
        address destination,
        address swapper,
        address vconRecipient
    ) external;

    /// @notice permissionlessly rebalance PCV based on
    /// the pre-existing VCON weights. Each movement must make
    /// the system more balanced, otherwise it will revert
    /// causing the entire transaction to fail.
    /// @param movements of PCV between venues
    function rebalance(Rebalance[] calldata movements) external;

    /// @notice realize gains and losses for msg.sender
    /// @param venues to realize losses in
    /// only the caller can realize losses on their own behalf
    /// duplicating addresses does not allow theft as all venues have their indexes
    /// updated before we find the profit and loss, so a duplicate venue will have 0 delta a second time
    /// @dev we can't follow CEI here because we have to make external calls to update
    /// the external venues. However, this is not an issue as the global reentrancy lock is enabled
    function realizeGainsAndLosses(address[] calldata venues) external;

    /// return the total amount of rewards a user is entitled to
    /// this value will usually be stale as .accrue() must be called in the same block/tx as this function
    /// for it to return the proper amount of profit
    function getAccruedRewards(
        address[] calldata venues,
        address user
    ) external view returns (int256);
}
