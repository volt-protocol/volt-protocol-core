// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {Constants} from "@voltprotocol/Constants.sol";
import {PCVRouter} from "@voltprotocol/pcv/PCVRouter.sol";
import {CoreRefV2} from "@voltprotocol/refs/CoreRefV2.sol";
import {IPCVOracle} from "@voltprotocol/oracle/IPCVOracle.sol";
import {IPCVDeposit} from "@voltprotocol/pcv/IPCVDeposit.sol";
import {IPCVDepositV2} from "@voltprotocol/pcv/IPCVDepositV2.sol";
import {IMarketGovernance} from "@voltprotocol/vcon/IMarketGovernance.sol";
import {DeviationWeiGranularity} from "@voltprotocol/utils/DeviationWeiGranularity.sol";

import {console} from "@forge-std/console.sol";

/// @notice this contract requires the PCV Mover and Locker role
///
/// Formula for market governance rewards share price:
///     Profit Per VCON = Profit Per VCON + ∆Cumulative Profits (Dollars) * VCON:Dollar  / VCON Staked
///
/// If an account has an unrealized loss on a venue, they cannot do any other action on that venue
/// until they have called the function realizeLosses and marked down the amount of VCON they have staked
/// on that venue. Once the loss has been marked down, they can proceed with other actions.
///
/// The VCON:Dollar ratio is the same for both profits and losses. If a venue has a VCON:Dollar ratio of 5:1
/// and the venue gains $5 in profits, then 25 VCON will be distributed across all VCON stakers in that venue.
/// If that same venue losses $5, then a loss of 25 VCON will be distributed across all VCON stakers in that venue.
///
/// @dev this contract assumes it is already topped up with the VCON necessary to pay rewards.
/// A dripper will keep this contract funded at a steady pace.
///
/// Issues I'm seeing so far
/// 1. if a loss occurs in a venue, then everyone's VCON balance gets marked down.
/// However, mark downs only occur when a loss is realized. This means unstaking after you have first realized
/// a loss and someone else hasn't, your pro-rata portion will be less, because the amount of VCON you have staked
/// has gone down.
/// 2. if a gain occurs, everyone's VCON balance marks up.
/// However, mark ups only occur when a gain is realized. This means unstaking after you have realized a gain and
/// someone else hasn't, your pro-rata portion of the PCV will be more than it would be if everyone had realized
/// their gains.
contract MarketGovernance is CoreRefV2, IMarketGovernance {
    using DeviationWeiGranularity for *;
    using SafeERC20 for *;
    using SafeCast for *;

    /// @notice reference to the PCV Router
    address public pcvRouter;

    /// @notice total amount of VCON deposited across all venues
    uint256 public vconStaked;

    /// @dev convention for all normal mappings is key (venue -> value)

    /// @notice amount of VCON paid per unit of revenue generated per venue
    /// different venues may have different ratios to account for rewards
    /// which will not be included in the V1
    mapping(address => uint256) public profitToVconRatio;

    /// and do the conversion to VCON at the end when accruing rewards
    /// pack venueLastRecordedProfit, venueVconDeposited and profitToVconRatio
    /// into a single slot for gas optimization

    /// @notice last recorded profit index per venue
    mapping(address => uint128) public venueLastRecordedProfit;

    /// @notice last recorded VCON share price index per venue
    mapping(address => uint128) public venueLastRecordedVconSharePrice;

    /// @notice total vcon deposited per venue
    mapping(address => uint256) public venueVconDeposited;

    /// ---------- Per Venue User Profit Tracking ----------

    /// @dev convention for all double nested address mappings is key (venue -> user) -> value

    /// @notice record of VCON index when user joined a given venue
    mapping(address => mapping(address => uint256))
        public venueUserVconStartingSharePrice;

    /// @notice record how much VCON a user deposited in a given venue
    mapping(address => mapping(address => uint256))
        public venueUserDepositedVcon;

    /// @param _core reference to core
    /// @param _pcvRouter reference to pcvRouter
    constructor(address _core, address _pcvRouter) CoreRefV2(_core) {
        pcvRouter = _pcvRouter;
    }

    /// TODO update pcv oracle to cache total pcv so getAllPCV isn't needed to figure
    /// out if weights are correct

    /// @notice update the VCON share price and the last recorded profit for a given venue
    /// @param venue address to accrue
    function accrueVcon(address venue) external globalLock(1) {
        IPCVOracle oracle = pcvOracle();

        require(oracle.isVenue(venue), "MarketGovernance: invalid destination");

        _accrue(venue);
    }

    /// ---------- Permissionless User PCV Allocation Methods ----------

    /// @notice a user can get slashed up to their full VCON stake for entering
    /// a venue that takes a loss.
    /// any losses or gains are applied to venueUserVconStartingSharePrice via `_accrue` method
    /// @param amountVcon to stake on destination
    /// @param destination address to accrue rewards to, and send funds to
    function stake(
        uint256 amountVcon,
        address destination
    ) external globalLock(1) {
        IPCVOracle oracle = pcvOracle();
        require(
            oracle.isVenue(destination),
            "MarketGovernance: invalid destination"
        );

        _accrue(destination); /// update profitPerVCON in the destination so the user gets in at the current share price
        int256 vconRewards = _updateUserProfitIndex(msg.sender, destination); /// auto-compound rewards
        require(
            vconRewards >= 0,
            "MarketGovernance: must realize loss before staking"
        );

        uint256 totalVconDeposited = amountVcon + vconRewards.toUint256(); /// auto-compound rewards

        /// global updates
        vconStaked += totalVconDeposited;

        /// user updates
        venueUserDepositedVcon[destination][msg.sender] += totalVconDeposited;

        /// venue updates
        venueVconDeposited[destination] += totalVconDeposited;

        /// check and an interaction with a trusted contract
        vcon().safeTransferFrom(msg.sender, address(this), amountVcon); /// transfer VCON in

        emit Staked(destination, msg.sender, amountVcon);
    }

    /// @notice unstake VCON and transfer corresponding VCON to another venue
    /// @param amountVcon the amount of VCON staked to unstake
    /// @param source address to accrue rewards to, and pull funds from
    /// @param destination address to send funds
    /// @param swapper address to swap funds through
    /// @param vconRecipient address to receive the VCON
    function unstake(
        uint256 amountVcon,
        address source,
        address destination,
        address swapper,
        address vconRecipient
    ) external globalLock(1) {
        /// ---------- Checks ----------

        IPCVOracle oracle = pcvOracle();

        require(oracle.isVenue(source), "MarketGovernance: invalid source");
        require(
            oracle.isVenue(destination),
            "MarketGovernance: invalid destination"
        );
        require(source != destination, "MarketGovernance: src and dest equal");

        /// ---------- Effects ----------

        _accrue(source); /// update profitPerVCON in the source so the user gets paid out at the current share price

        /// amount of PCV to withdraw is the amount vcon * venue balance / total vcon staked on venue
        uint256 amountPcv = getProRataPCVAmounts(source, amountVcon);

        int256 vconRewards = _updateUserProfitIndex(msg.sender, source); /// pay msg.sender their rewards
        uint256 vconReward = vconRewards.toUint256(); /// pay msg.sender their rewards

        require(
            vconRewards >= 0,
            "MarketGovernance: must realize loss before unstaking"
        );

        require(
            venueUserDepositedVcon[source][msg.sender] >= amountVcon,
            "MarketGovernance: invalid vcon amount"
        );

        /// global updates
        vconStaked -= amountVcon;

        /// user updates
        venueUserDepositedVcon[source][msg.sender] -= amountVcon;

        /// venue updates
        venueVconDeposited[source] -= amountVcon;

        /// ---------- Interactions ----------

        vcon().safeTransfer(vconRecipient, amountVcon + vconReward); /// transfer VCON amount + rewards to recipient

        /// ignore balance checks if only one user is in the system and is allocating to a single venue
        bool ignoreBalanceChecks = vconStaked ==
            venueUserDepositedVcon[source][msg.sender];

        _movePCVWithChecks(
            source,
            destination,
            swapper,
            amountPcv,
            ignoreBalanceChecks
        );

        emit Unstaked(source, msg.sender, amountVcon, amountPcv);
    }

    /// @notice rebalance PCV without staking or unstaking VCON
    /// each individual action must make the system more balanced
    /// as a whole, otherwise it will revert
    /// @param movements information on all pcv movements
    /// including sources, destinations, amounts and swappers
    function rebalance(Rebalance[] calldata movements) external globalLock(1) {
        unchecked {
            for (uint256 i = 0; i < movements.length; i++) {
                address source = movements[i].source;
                address destination = movements[i].destination;
                address swapper = movements[i].swapper;
                uint256 amountPcv = movements[i].amountPcv;

                _movePCVWithChecks(
                    source,
                    destination,
                    swapper,
                    amountPcv,
                    false
                );
            }
        }
    }

    /// @notice realize gains and losses for msg.sender
    /// @param venues to realize losses in
    /// only the caller can realize losses on their own behalf
    /// duplicating addresses does not allow theft as all venues have their indexes
    /// updated before we find the profit and loss, so a duplicate venue will have 0 delta a second time
    /// @dev we can't follow CEI here because we have to make external calls to update
    /// the external venues. However, this is not an issue as the global reentrancy lock is enabled
    function realizeGainsAndLosses(
        address[] calldata venues
    ) external globalLock(1) {
        uint256 venueLength = venues.length;
        uint256 totalVcon = 0;

        for (uint256 i = 0; i < venueLength; ) {
            address venue = venues[i];
            require(
                pcvOracle().isVenue(venue),
                "MarketGovernance: invalid venue"
            );

            /// updates the venueLastRecordedProfit
            _accrue(venue);

            /// updates the venueUserVconStartingSharePrice mapping
            int256 pnl = _updateUserProfitIndex(msg.sender, venue);
            if (pnl < 0) {
                uint256 lossAmount;
                /// loss scenarios
                if (
                    (-pnl).toUint256() >
                    venueUserDepositedVcon[venue][msg.sender]
                ) {
                    uint256 userDepositedAmount = venueUserDepositedVcon[venue][
                        msg.sender
                    ];
                    /// zero the user's balance
                    venueUserDepositedVcon[venue][msg.sender] = 0;

                    /// take losses off the total amount staked
                    vconStaked -= userDepositedAmount;

                    /// final write to storage, decrement venue deposited VCON
                    venueVconDeposited[venue] -= userDepositedAmount;

                    lossAmount = userDepositedAmount;
                } else {
                    /// losses should never exceed staked amount at this point
                    venueUserDepositedVcon[venue][
                        msg.sender
                    ] = (venueUserDepositedVcon[venue][msg.sender].toInt256() +
                        pnl).toUint256();

                    /// take losses off the total amount staked
                    vconStaked = (vconStaked.toInt256() + pnl).toUint256();

                    /// decrement venue deposited VCON
                    venueVconDeposited[venue] -= (-pnl).toUint256();

                    lossAmount = (-pnl).toUint256();
                }

                emit LossRealized(venue, msg.sender, lossAmount);
            } else {
                /// gain or even scenario
                totalVcon += pnl.toUint256();
                if (pnl != 0) {
                    emit Harvest(venue, msg.sender, pnl);
                }
            }

            unchecked {
                i++;
            }
        }

        if (totalVcon != 0) {
            vcon().safeTransfer(msg.sender, totalVcon);
        }
    }

    /// ------------- View Only Methods -------------

    /// @notice returns positive value if over allocated
    /// returns negative value if under allocated
    /// if no venue balance and deposited vcon, return positive
    /// if venue balance and no deposited vcon, return negative
    ///
    /// algorithm for determining how balanced a venue is:
    ///
    /// 1. get ratio of how much vcon is deposited into the venue out of the total supply
    /// a = venue deposited vcon / total vcon staked
    ///
    /// 2. get expected amount of pcv in the venue based on the vcon staked in that venue and the total pcv
    /// b = a * total pcv
    ///
    /// 3. find the delta in percentage terms, scaled by 1 ether between the expected amount of pcv in the
    ///  venue vs the actual amount in the venue
    /// d = (a - b)  / a
    ///
    /// @param venue to query
    /// @param totalPcv to measure venue against
    function getVenueDeviation(
        address venue,
        uint256 totalPcv
    ) public view returns (int256) {
        uint256 venueDepositedVcon = venueVconDeposited[venue];
        uint256 venueBalance = pcvOracle().getVenueBalance(venue);
        uint256 cachedVconStaked = vconStaked;

        /// 0 checks as any 0 denominator will cause a revert
        if (
            (venueDepositedVcon == 0 && venueBalance == 0) ||
            cachedVconStaked == 0 ||
            totalPcv == 0
        ) {
            return 0; /// perfectly balanced at 0 PCV or 0 VCON staked
        }

        /// Step 1.
        /// find out actual ratio of VCON in a given venue based on total VCON staked
        uint256 venueDepositedVconRatio = (venueDepositedVcon *
            Constants.ETH_GRANULARITY) / cachedVconStaked;

        /// perfectly balanced
        if (venueDepositedVconRatio == 0 && venueBalance == 0) {
            return 0;
        }

        if (venueDepositedVconRatio == 0) {
            /// add this 0 check because deviation divides by a and would cause a revert
            /// replicate step 3 if no VCON is deposited by comparing pcv to venue balance
            return Constants.ETH_GRANULARITY_INT;
        }

        /// Step 2.
        /// get expected pcv amount
        uint256 expectedPcvAmount = (venueDepositedVconRatio * totalPcv) /
            Constants.ETH_GRANULARITY;

        /// perfectly balanced = (expectedPcvAmount - venueBalance) * 1e18 / expectedPcvAmount = 0

        /// Step 3.
        /// if venue deposited VCON, return the ratio between expected pcv vs actual pcv
        return
            -DeviationWeiGranularity.calculateDeviation(
                expectedPcvAmount.toInt256(),
                venueBalance.toInt256()
            );
    }

    /// @param venue to figure out total pro rata pcv
    /// @param amountVcon to find total amount of pro rata pcv
    /// @return the pro rata pcv controll  ed in the given venue based on the amount of VCON
    function getProRataPCVAmounts(
        address venue,
        uint256 amountVcon
    ) public view returns (uint256) {
        uint256 venuePcv = IPCVDeposit(venue).balance();
        uint256 cachedVconStaked = venueVconDeposited[venue];

        /// 0 checks as any 0 denominator will cause a revert
        if (cachedVconStaked == 0) {
            return 0; /// perfectly balanced at 0 PCV or 0 VCON staked
        }

        /// @audit we do not add 1 to the pro rata PCV here. This means a withdrawal of 1 Wei of VCON
        /// will allow removing a user's VCON without having to withdraw PCV from a venue.
        /// This is a known issue, however it is not harmful as it would require a quintillion withdrawals
        /// to withdraw 1 VCON, which would cost at minimum 5,000e18 gas per withdraw, meaning it would cost at least 1 million ether
        /// (likely more) to retrieve a single VCON without moving PCV.
        /// The only reason this would ever get expoited is if a loss was taken and a user was trying to avoid realizing their portion
        /// of the losses. However, in a loss scenario, the unstake function does not allow execution if the user has an unrealized
        /// loss in that venue. This condition stops the aforementioned exploit.
        /// fix would require rounding up in the protocol's favor, so that a withdrawal of 1 Wei of VCON has an actual withdraw amount
        uint256 proRataPcv = (amountVcon * venuePcv) / cachedVconStaked;

        return proRataPcv;
    }

    /// @notice return the amount of rewards accrued so far
    /// without calling accrue on the underlying venues
    function getAccruedRewards(
        address[] calldata venues,
        address user
    ) external view returns (int256 totalVcon) {
        uint256 venueLength = venues.length;

        unchecked {
            for (uint256 i = 0; i < venueLength; i++) {
                address venue = venues[i];
                require(
                    pcvOracle().isVenue(venue),
                    "MarketGovernance: invalid venue"
                );

                totalVcon += getPendingRewards(user, venue);
            }
        }
    }

    struct PCVDepositInfo {
        address deposit;
        uint256 amount;
    }

    /// @notice return what the perfectly balanced system would look like
    function getExpectedPCVAmounts()
        public
        view
        returns (PCVDepositInfo[] memory deposits)
    {
        address[] memory pcvDeposits = pcvOracle().getVenues();
        uint256 totalVenues = pcvDeposits.length;
        uint256 totalPcv = pcvOracle().getTotalPcv();
        uint256 cachedVconStaked = vconStaked; /// Save repeated warm SLOADs

        deposits = new PCVDepositInfo[](totalVenues);

        unchecked {
            for (uint256 i = 0; i < totalVenues; i++) {
                address venue = pcvDeposits[i];
                uint256 venueDepositedVcon = venueVconDeposited[venue];
                deposits[i].deposit = venue;

                if (venueDepositedVcon == 0) {
                    deposits[i].amount = 0;
                } else {
                    uint256 expectedPcvAmount = (venueDepositedVcon *
                        totalPcv) / cachedVconStaked;

                    deposits[i].amount = expectedPcvAmount;
                }
            }
        }
    }

    /// @notice VCON rewards could be negative if a user is at a loss
    /// @param user to check rewards from
    /// @param venue to check rewards in
    /// return the amount of pending rewards or losses for a given user
    /// algorithm:
    ///  1. Determine venue profits or losses that have occured since
    ///   the last time the user staked or unstaked in a given venue.
    ///      venue pnl = current profit index - user starting index
    ///  2. Convert PnL to their pro-rata VCON amount
    ///      vcon rewards = venue PnL * user vcon deposited in venue / total vcon deposited in venue
    function getPendingRewards(
        address user,
        address venue
    ) public view returns (int256) {
        /// get user starting share price
        int256 startingVconSharePrice = venueUserVconStartingSharePrice[venue][
            user
        ].toInt256();

        /// get venue current share price
        int256 currentVconSharePrice = venueLastRecordedVconSharePrice[venue]
            .toInt256();

        /// get venue vcon amount staked
        int256 venueVconAmount = venueVconDeposited[venue].toInt256();

        if (startingVconSharePrice == 0 || venueVconAmount == 0) {
            return 0; /// no interest if user has not entered the market
        }

        int256 userCurrentProfitPerVcon = currentVconSharePrice -
            startingVconSharePrice;

        int256 vconRewards = (userCurrentProfitPerVcon *
            venueUserDepositedVcon[venue][user].toInt256()) /
            Constants.ETH_GRANULARITY_INT;

        return vconRewards;
    }

    /// ------------- Helper Methods -------------

    /// @param source address to pull funds from
    /// @param destination recipient address for funds
    /// @param swapper address to swap tokens with
    /// @param amountPcv the amount of PCV to move from source
    /// @param ignoreBalanceChecks whether or not to ignore balance checks
    function _movePCVWithChecks(
        address source,
        address destination,
        address swapper,
        uint256 amountPcv,
        bool ignoreBalanceChecks
    ) private {
        address sourceAsset = IPCVDepositV2(source).balanceReportedIn();
        address destinationAsset = IPCVDepositV2(destination)
            .balanceReportedIn();

        /// read unsafe because we are at lock level 1
        uint256 totalPcv = pcvOracle().getTotalPcvUnsafe();

        int256 sourceVenueBalance;
        int256 destinationVenueBalance;

        if (!ignoreBalanceChecks) {
            /// record how balanced the system is before the PCV movement
            sourceVenueBalance = getVenueDeviation(source, totalPcv); /// 50%
            destinationVenueBalance = getVenueDeviation(destination, totalPcv); /// -30%
        }

        /// validate pcv movement
        /// check underlying assets match up and if not that swapper is provided and valid
        PCVRouter(pcvRouter).movePCV(
            source,
            destination,
            swapper,
            amountPcv,
            sourceAsset,
            destinationAsset
        );

        if (!ignoreBalanceChecks) {
            /// TODO simplify this by passing delta of starting balance
            /// instead of calling balance again on each pcv deposit
            /// record how balanced the system is before the PCV movement
            int256 sourceVenueBalanceAfter = getVenueDeviation(
                source,
                totalPcv
            );
            int256 destinationVenueBalanceAfter = getVenueDeviation(
                destination,
                totalPcv
            );

            /// source and dest venue balance measures the distance from being perfectly balanced

            /// validate source venue balance became more balanced
            _checkBalance(
                sourceVenueBalance,
                sourceVenueBalanceAfter,
                "MarketGovernance: src more imbalanced"
            );

            /// validate destination venue balance became more balanced
            _checkBalance(
                destinationVenueBalance,
                destinationVenueBalanceAfter,
                "MarketGovernance: dest more imbalanced"
            );
        }
    }

    /// @notice helper function to validate balance moved in the right direction after a pcv movement
    function _checkBalance(
        int256 balanceBefore,
        int256 balanceAfter,
        string memory reason
    ) private pure {
        require(
            balanceBefore < 0 /// if balance is under weight relative to vcon staked, ensure it doesn't go over balance
                ? balanceAfter > balanceBefore && balanceAfter <= 0 /// if balance is over weight relative to vcon staked, ensure it doesn't go under balance
                : balanceAfter < balanceBefore && balanceAfter >= 0,
            reason
        );
    }

    /// @notice returns profit or losses a VCON staker has accrued
    /// updates their venue starting profit index
    /// does not update how much VCON a user has staked to save on gas
    /// that updating happens in the calling function
    function _updateUserProfitIndex(
        address user,
        address venue
    ) private returns (int256) {
        uint256 currentVenueSharePrice = venueLastRecordedVconSharePrice[venue];

        /// get pending rewards
        int256 pendingRewardBalance = getPendingRewards(user, venue);

        /// then set the vcon share price for this user
        venueUserVconStartingSharePrice[venue][user] = currentVenueSharePrice;

        /// emit harvest if there are gains or losses
        emit Harvest(venue, user, pendingRewardBalance);

        return pendingRewardBalance;
    }

    /// update the venue last recorded profit
    /// and the venue last recorded vcon share price
    function _accrue(address venue) private {
        IPCVDepositV2(venue).accrue();

        uint256 startingLastRecordedProfit = venueLastRecordedProfit[venue];
        uint256 endingLastRecordedProfit = IPCVDepositV2(venue)
            .lastRecordedProfit();
        uint256 endingLastRecordedSharePrice = venueLastRecordedVconSharePrice[
            venue
        ];

        /// update venue last recorded profit regardless
        /// of participation in market governance
        if (endingLastRecordedSharePrice != 0) {
            uint256 venueStakedVcon = venueVconDeposited[venue];
            uint256 venueProfitRatio = profitToVconRatio[venue];

            /// if venue has 0 staked vcon, do not update share price, just update profit index
            if (venueStakedVcon != 0) {
                int256 venueProfit = (endingLastRecordedProfit.toInt256() -
                    startingLastRecordedProfit.toInt256());
                int256 vconEarnedPerShare = (Constants.ETH_GRANULARITY_INT *
                    venueProfit *
                    venueProfitRatio.toInt256()) / venueStakedVcon.toInt256();

                if (vconEarnedPerShare >= 0) {
                    /// gain scenario
                    venueLastRecordedVconSharePrice[venue] += (
                        vconEarnedPerShare.toUint256()
                    ).toUint128();
                } else {
                    /// loss scenario
                    /// turn losses positive and subtract them
                    venueLastRecordedVconSharePrice[venue] -= (
                        -vconEarnedPerShare
                    ).toUint256().toUint128();
                }
            }
        } else {
            /// share price is 0, meaning it is not initialized, so initialize
            venueLastRecordedVconSharePrice[venue] = Constants
                .ETH_GRANULARITY
                .toUint128();
        }

        venueLastRecordedProfit[venue] = endingLastRecordedProfit.toUint128();

        emit VenueIndexUpdated(
            venue,
            block.timestamp,
            endingLastRecordedProfit
        );
    }

    /// ---------- Governor-Only Permissioned API ----------

    function setProfitToVconRatio(
        address venue,
        uint256 newProfitToVconRatio
    ) external onlyGovernor {
        uint256 oldProfitToVconRatio = profitToVconRatio[venue];
        profitToVconRatio[venue] = newProfitToVconRatio;

        emit ProfitToVconRatioUpdated(
            venue,
            oldProfitToVconRatio,
            newProfitToVconRatio
        );
    }

    function setPCVRouter(address newPcvRouter) external onlyGovernor {
        address oldPcvRouter = pcvRouter;
        pcvRouter = newPcvRouter;

        emit PCVRouterUpdated(oldPcvRouter, newPcvRouter);
    }
}
