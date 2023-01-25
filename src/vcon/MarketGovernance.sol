// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {PCVMover} from "@voltprotocol/pcv/PCVMover.sol";
import {Constants} from "@voltprotocol/Constants.sol";
import {CoreRefV2} from "@voltprotocol/refs/CoreRefV2.sol";
import {IPCVOracle} from "@voltprotocol/oracle/IPCVOracle.sol";
import {IPCVDeposit} from "@voltprotocol/pcv/IPCVDeposit.sol";
import {IPCVDepositV2} from "@voltprotocol/pcv/IPCVDepositV2.sol";
import {IMarketGovernance} from "@voltprotocol/vcon/IMarketGovernance.sol";
import {DeviationWeiGranularity} from "@voltprotocol/utils/DeviationWeiGranularity.sol";

import {console} from "@forge-std/console.sol";

/// @notice this contract requires the PCV Controller and Locker role
///
/// Core formula for market governance rewards:
///     Profit Per VCON = Profit Per VCON + ∆Cumulative Profits (Dollars) * VCON:Dollar  / VCON Staked
///
/// If an account has an unrealized loss on a venue, they cannot do any other action on that venue
/// until they have called the function realizeLosses and marked down the amount of VCON they have staked
/// on that venue. Once the loss has been marked down, they can proceed with other actions.
///
/// The VCON:Dollar ratio is the same for both profits and losses. If a venue has a VCON:Dollar ratio of 5:1
/// and the venue gains $5 in profits, then 25 VCON will be distributed across all VCON stakers in that venue.
/// If that same venue losses $5, then a loss of 25 VCON will be distributed across all VCON stakers in that venue.
contract MarketGovernance is CoreRefV2, PCVMover, IMarketGovernance {
    using DeviationWeiGranularity for *;
    using SafeERC20 for *;
    using SafeCast for *;

    /// @notice emitted when a route is added
    event RouteAdded(
        address indexed src,
        address indexed dst,
        address indexed swapper
    );

    /// @notice emitted when profit to vcon ratio is updated
    event ProfitToVconRatioUpdated(
        address indexed venue,
        uint256 oldRatio,
        uint256 newRatio
    );

    /// @notice total amount of VCON deposited across all venues
    uint256 public vconStaked;

    /// @dev convention for all normal mappings is key (venue -> value)

    /// @notice amount of VCON paid per unit of revenue generated per venue
    /// different venues may have different ratios to account for rewards
    /// which will not be included in the V1
    mapping(address => uint256) public profitToVconRatio;

    /// TODO simplify this contract down to only track venue profit,
    /// and do the conversion to VCON at the end when accruing rewards
    /// alternatively, pack venueLastRecordedSharePrice,
    /// venueLastRecordedProfit and venueVconDeposited into a single slot for gas optimization

    /// @notice last recorded profit index per venue
    mapping(address => uint128) public venueLastRecordedProfit;

    /// @notice last recorded share price of a venue in VCON
    /// starts off at 1e18
    mapping(address => uint128) public venueLastRecordedSharePrice;

    /// @notice total vcon deposited per venue
    mapping(address => uint256) public venueVconDeposited;

    /// ---------- Per Venue User Profit Tracking ----------

    /// @dev convention for all double nested address mappings is key (venue -> user) -> value

    /// @notice record of VCON index when user joined a given venue
    mapping(address => mapping(address => uint256))
        public venueUserStartingVconProfit;

    /// @notice record how much VCON a user deposited in a given venue
    mapping(address => mapping(address => uint256))
        public venueUserDepositedVcon;

    /// @param _core reference to core
    constructor(address _core) CoreRefV2(_core) {}

    /// @notice permissionlessly initialize a venue
    /// required to be able to utilize a given PCV Deposit in market governance
    function initializeVenue(address venue) external globalLock(1) {
        require(pcvOracle().isVenue(venue), "MarketGovernance: invalid venue");

        uint256 startingLastRecordedProfit = venueLastRecordedProfit[venue];
        require(
            startingLastRecordedProfit == 0,
            "MarketGovernance: profit already recorded"
        );
        require(
            venueLastRecordedSharePrice[venue] == 0,
            "MarketGovernance: venue already has share price"
        );

        IPCVDepositV2(venue).accrue();

        uint256 endingLastRecordedProfit = IPCVDepositV2(venue)
            .lastRecordedProfit();

        venueLastRecordedProfit[venue] = endingLastRecordedProfit.toUint128();
        venueLastRecordedSharePrice[venue] = Constants
            .ETH_GRANULARITY
            .toUint128();
    }

    /// TODO update pcv oracle to cache total pcv so getAllPCV isn't needed to figure
    /// out if weights are correct

    /// ---------- Permissionless User PCV Allocation Methods ----------

    /// any losses or gains are applied to venueLastRecordedSharePrice
    ///
    ///
    /// user deposits

    /// @notice a user can get slashed up to their full VCON stake for entering
    /// a venue that takes a loss.
    /// @param amountVcon to stake on destination
    /// @param amountPcv to move from source to destination
    /// @param source address to pull funds from
    /// @param destination address to accrue rewards to, and send funds to
    /// @param swapper address that swaps asset types between src and dest if needed
    function stake(
        uint256 amountVcon,
        uint256 amountPcv,
        address source,
        address destination,
        address swapper
    ) external globalLock(1) {
        IPCVOracle oracle = pcvOracle();
        require(oracle.isVenue(source), "MarketGovernance: invalid source");
        require(
            oracle.isVenue(destination),
            "MarketGovernance: invalid destination"
        );
        require(source != destination, "MarketGovernance: src and dest equal");

        _accrue(destination); /// update profitPerVCON in the destination so the user gets in at the current share price
        int256 vconRewards = _harvestRewards(msg.sender, destination); /// auto-compound rewards
        require(
            vconRewards >= 0,
            "MarketGovernance: must realize loss before staking"
        );

        /// check and an interaction with a trusted contract
        vcon().safeTransferFrom(msg.sender, address(this), amountVcon); /// transfer VCON in

        uint256 totalVconDeposited = amountVcon + vconRewards.toUint256(); /// auto-compound rewards

        /// global updates
        vconStaked += totalVconDeposited;

        /// user updates
        venueUserDepositedVcon[destination][msg.sender] += totalVconDeposited;

        /// venue updates
        venueVconDeposited[destination] += totalVconDeposited;

        /// ignore balance checks if only one user is allocating in the system
        bool ignoreBalanceChecks = vconStaked == totalVconDeposited;

        if (amountPcv != 0) {
            _movePCVWithChecks(
                source,
                destination,
                swapper,
                amountPcv,
                ignoreBalanceChecks
            );
        }
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

        int256 vconRewards = _harvestRewards(msg.sender, source); /// pay msg.sender their rewards
        uint256 vconReward = vconRewards.toUint256(); /// pay msg.sender their rewards

        require(
            vconRewards >= 0,
            "MarketGovernance: must realize loss before unstaking"
        );

        require(
            venueUserDepositedVcon[source][msg.sender] + vconReward >=
                amountVcon,
            "MarketGovernance: invalid vcon amount"
        );

        /// global updates
        vconStaked -= amountVcon;

        /// user updates
        /// balance = 80
        /// amount = 100
        /// rewards = 30
        /// amount deducted = 70
        /// _____________
        /// balance = 10
        venueUserDepositedVcon[source][msg.sender] -= amountVcon - vconReward;

        /// venue updates
        venueVconDeposited[source] -= amountVcon;

        /// ---------- Interactions ----------

        vcon().safeTransfer(vconRecipient, amountVcon); /// transfer VCON to recipient

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

    /// TODO add slashing logic to burn VCON from participants that are in a venue that took a loss

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
    /// 3. find the delta in basis points between the expected amount of pcv in the venue vs the actual amount in the venue
    /// d = (a - b)  / a
    ///
    /// @param venue to query
    /// @param totalPcv to measure venue against
    function getVenueBalance(
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
            return
                DeviationWeiGranularity.calculateDeviation(
                    totalPcv.toInt256(),
                    venueBalance.toInt256()
                );
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

        console.log("cachedVconStaked: ", cachedVconStaked);

        /// 0 checks as any 0 denominator will cause a revert
        if (cachedVconStaked == 0) {
            return 0; /// perfectly balanced at 0 PCV or 0 VCON staked
        }

        uint256 proRataPcv = (amountVcon * venuePcv) / cachedVconStaked;

        return proRataPcv;
    }

    struct PCVDepositInfo {
        address deposit;
        uint256 amount;
    }

    /// apply the amount of rewards a user has accrued, sending directly to their account
    /// each venue will have the accrue function called in order to get the most up to
    /// date pnl from them
    function applyRewards(
        address[] calldata venues,
        address user
    ) external globalLock(1) {
        uint256 venueLength = venues.length;
        int256 totalVcon = 0;

        unchecked {
            for (uint256 i = 0; i < venueLength; i++) {
                address venue = venues[i];
                require(
                    pcvOracle().isVenue(venue),
                    "MarketGovernance: invalid venue"
                );

                _accrue(venue);
                int256 rewards = _harvestRewards(user, venue);
                require(
                    rewards >= 0,
                    "MarketGovernance: cannot claim rewards on venue with losses"
                );
                totalVcon += rewards;
            }
        }

        /// rewards was never less than 0, so totalVcon must be >= 0
        vcon().safeTransfer(user, totalVcon.toUint256());
    }

    /// @param venues to realize losses in
    /// only the caller can realize losses on their own behalf
    function realizeLosses(address[] calldata venues) external globalLock(1) {
        uint256 venueLength = venues.length;

        unchecked {
            for (uint256 i = 0; i < venueLength; i++) {
                address venue = venues[i];
                require(
                    pcvOracle().isVenue(venue),
                    "MarketGovernance: invalid venue"
                );

                /// updates the venueLastRecordedProfit and venueLastRecordedSharePrice mapping
                _accrue(venue);

                /// updates the venueUserStartingVconProfit mapping
                int256 losses = _harvestRewards(msg.sender, venue);
                require(losses < 0, "MarketGovernance: no losses to realize");

                if (
                    (-losses).toUint256() >
                    venueUserDepositedVcon[venue][msg.sender]
                ) {
                    uint256 userDepositedAmount = venueUserDepositedVcon[venue][
                        msg.sender
                    ];
                    /// zero the user's balance
                    venueUserDepositedVcon[venue][msg.sender] = 0;

                    /// take losses off the total amount staked
                    vconStaked -= userDepositedAmount;
                } else {
                    /// losses should never exceed staked amount at this point
                    venueUserDepositedVcon[venue][
                        msg.sender
                    ] = (venueUserDepositedVcon[venue][msg.sender].toInt256() +
                        losses).toUint256();

                    /// take losses off the total amount staked
                    vconStaked = (vconStaked.toInt256() + losses).toUint256();
                }
            }
        }
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
            sourceVenueBalance = getVenueBalance(source, totalPcv); /// 50%
            destinationVenueBalance = getVenueBalance(destination, totalPcv); /// -30%
        }

        /// validate pcv movement
        /// check underlying assets match up and if not that swapper is provided and valid
        _checkPCVMove(
            source,
            destination,
            swapper,
            sourceAsset,
            destinationAsset
        );

        /// optimistically transfer funds to the specified pcv deposit
        _movePCV(
            source,
            destination,
            swapper,
            amountPcv,
            sourceAsset,
            destinationAsset
        );

        if (!ignoreBalanceChecks) {
            /// TODO simplify this by passing delta of starting balance instead of calling balance again on each pcv deposit
            /// record how balanced the system is before the PCV movement
            int256 sourceVenueBalanceAfter = getVenueBalance(source, totalPcv);
            int256 destinationVenueBalanceAfter = getVenueBalance(
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

    /// @notice VCON rewards could be negative if a user is at a loss
    /// @param user to check rewards from
    /// @param venue to check rewards in
    function getPendingRewards(
        address user,
        address venue
    ) public view returns (int256) {
        int256 vconStartIndex = venueUserStartingVconProfit[venue][user]
            .toInt256();
        int256 vconCurrentIndex = venueLastRecordedSharePrice[venue].toInt256();

        if (vconStartIndex == 0) {
            return 0; /// no interest if user has not entered the market
        }

        int256 vconRewards = (vconCurrentIndex - vconStartIndex) *
            venueUserDepositedVcon[venue][user].toInt256();

        return vconRewards;
    }

    /// @notice returns profit in VCON a user has accrued
    /// does not update how much VCON a user has staked to save on gas
    /// that updating happens in the calling function
    function _harvestRewards(
        address user,
        address venue
    ) private returns (int256) {
        uint256 vconCurrentIndex = venueLastRecordedSharePrice[venue];

        console.log("getting pending rewards");
        /// get pending rewards
        int256 pendingRewardBalance = getPendingRewards(user, venue);
        console.log("got pending rewards", pendingRewardBalance.toUint256());

        /// then set the vcon current index for this user
        venueUserStartingVconProfit[venue][user] = vconCurrentIndex;

        return pendingRewardBalance;
    }

    /// update the venue last recorded share price
    function _accrue(address venue) private {
        uint256 startingLastRecordedProfit = venueLastRecordedProfit[venue];

        IPCVDepositV2(venue).accrue();

        uint256 endingLastRecordedProfit = IPCVDepositV2(venue)
            .lastRecordedProfit();

        /// update venue last recorded profit regardless
        /// of participation in market governance
        venueLastRecordedProfit[venue] = endingLastRecordedProfit.toUint128();

        /// amount of VCON that each VCON deposit receives for being in this venue
        /// if there is no supply, there is no delta to apply
        if (vconStaked != 0) {
            int256 deltaProfit = endingLastRecordedProfit.toInt256() -
                startingLastRecordedProfit.toInt256(); /// also could be a loss

            int256 venueProfitToVconRatio = profitToVconRatio[venue].toInt256();

            int256 profitPerVconDelta = (deltaProfit * venueProfitToVconRatio) /
                vconStaked.toInt256();

            uint256 lastVconSharePrice = venueLastRecordedSharePrice[venue];
            require(
                lastVconSharePrice >= Constants.ETH_GRANULARITY,
                "MarketGovernance: venue not initialized"
            );

            venueLastRecordedSharePrice[venue] = (lastVconSharePrice
                .toInt256() + profitPerVconDelta).toUint256().toUint128();
        }
    }

    /// TODO add events

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
}
