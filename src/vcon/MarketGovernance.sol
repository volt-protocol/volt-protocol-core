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
/// three main data points are tracked in each venue.
/// 1. the last recorded profit in a given venue. this tracks the last recorded profit amount in the underlying venue.
/// 2. the vcon share price in a given venue. this applies the last recorded profit across all VCON stakers in the
/// venue evenly and ensures that each user receives their pro-rata share of rewards.
/// 3. profit to vcon ratio in each venue. this tracks the profit to vcon ratio for each venue and is used to calculate
/// the vcon share price by finding the new last recorded profit, and finding the profit delta
/// vcon share price formula
///
/// Formula for market governance rewards share price:
///     ∆Cumulative Profits (Dollars) = currentProfits - lastRecordedProfits
///     Profit Per VCON = Profit Per VCON + ∆Cumulative Profits (Dollars) * VCON:Dollar Ratio / Venue VCON Staked
///
/// Formula for calculating user VCON rewards:
///     User VCON rewards = (Profit Per VCON - User Starting Profit Per VCON) * VCON Staked
///
/// Anytime the rewards share price changes, so does the unclaimed user VCON rewards.
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

    /// @dev convention for all normal mappings is key (venue -> value)

    /// @notice amount of VCON paid per unit of revenue generated per venue
    /// different venues may have different ratios to account for rewards
    /// which will not be included in the V1
    mapping(address => uint256) public profitToVconRatio;

    /// and do the conversion to VCON at the end when accruing rewards
    /// pack venueLastRecordedProfit, venueTotalShares and profitToVconRatio
    /// into a single slot for gas optimization

    /// @notice last recorded profit index per venue
    mapping(address => uint128) public venueLastRecordedProfit;

    /// @notice last recorded VCON share price index per venue
    mapping(address => uint128) public venueLastRecordedVconSharePrice;

    /// @notice total vcon deposited per venue
    mapping(address => uint256) public venueTotalShares;

    /// ---------- Per Venue User Profit Tracking ----------

    /// @dev convention for all double nested address mappings is key (venue -> user) -> value

    /// @notice record how much VCON a user deposited in a given venue
    mapping(address => mapping(address => uint256)) public venueUserShares;

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

        _accrue(destination); /// update share price in the destination so the user gets in at the current share price

        /// vconToShares will always return correctly as accrue will set venueLastRecordedVconSharePrice
        /// to the correct share price from 0 if uninitialized
        uint256 userShareAmount = vconToShares(destination, amountVcon);

        /// user updates
        venueUserShares[destination][msg.sender] += userShareAmount;

        /// venue updates
        venueTotalShares[destination] += userShareAmount;

        /// check and an interaction with a trusted contract
        vcon().safeTransferFrom(msg.sender, address(this), amountVcon); /// transfer VCON in

        emit Staked(destination, msg.sender, amountVcon);
    }

    /// @notice unstake VCON and transfer corresponding VCON to another venue
    /// @param shareAmount the amount of shares to unstake
    /// @param source address to accrue rewards to, and pull funds from
    /// @param destination address to send funds
    /// @param swapper address to swap funds through
    /// @param vconRecipient address to receive the VCON
    function unstake(
        uint256 shareAmount,
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

        /// figure out how balanced the system is before withdraw

        /// amount of PCV to withdraw is the amount vcon * venue balance / total vcon staked on venue
        uint256 amountPcv = getProRataPCVAmounts(source, shareAmount);
        uint256 amountVcon = sharesToVcon(source, shareAmount);

        /// read unsafe because we are at lock level 1
        uint256 totalPcv = pcvOracle().getTotalPcvUnsafe();

        /// record how balanced the system is before the PCV movement
        uint256 totalVconStaked = getTotalVconStaked();

        uint256 sourceExpectedPcv = getExpectedVenuePCVAmount(
            source,
            totalPcv,
            totalVconStaked
        );
        uint256 destinationExpectedPcv = getExpectedVenuePCVAmount(
            source,
            totalPcv,
            totalVconStaked
        );

        int256 sourceVenueBalance = getVenueDeviation(
            source,
            sourceExpectedPcv
        );
        int256 destinationVenueBalance = getVenueDeviation(
            destination,
            destinationExpectedPcv
        );

        require(
            venueUserShares[source][msg.sender] >= shareAmount,
            "MarketGovernance: invalid share amount"
        );

        /// user updates
        venueUserShares[source][msg.sender] -= shareAmount;

        /// venue updates
        venueTotalShares[source] -= shareAmount;

        /// ---------- Interactions ----------

        vcon().safeTransfer(vconRecipient, amountVcon); /// transfer VCON amount to recipient

        _movePCVWithChecks(
            source,
            destination,
            swapper,
            amountPcv,
            totalPcv,
            sourceVenueBalance,
            destinationVenueBalance
        );

        emit Unstaked(source, msg.sender, amountVcon, amountPcv);
    }

    /// @notice rebalance PCV without staking or unstaking VCON
    /// each individual action must make the system more balanced
    /// as a whole, otherwise it will revert
    /// @param movements information on all pcv movements
    /// including sources, destinations, amounts and swappers
    function rebalance(Rebalance[] calldata movements) external globalLock(1) {
        /// read unsafe because we are at lock level 1
        uint256 totalPcv = pcvOracle().getTotalPcvUnsafe();

        unchecked {
            for (uint256 i = 0; i < movements.length; i++) {
                address source = movements[i].source;
                address destination = movements[i].destination;
                address swapper = movements[i].swapper;
                uint256 amountPcv = movements[i].amountPcv;
                /// record how balanced the system is before the PCV movement
                int256 sourceVenueBalance = getVenueDeviation(source, totalPcv);
                int256 destinationVenueBalance = getVenueDeviation(
                    destination,
                    totalPcv
                );

                _movePCVWithChecks(
                    source,
                    destination,
                    swapper,
                    amountPcv,
                    totalPcv,
                    sourceVenueBalance,
                    destinationVenueBalance
                );
            }
        }
    }

    /// ------------- View Only Methods -------------

    /// @param venue to get share price from
    /// @param shareAmount to withdraw
    /// @return vconAmount the amount of VCON received for a given amount of shares
    function sharesToVcon(
        address venue,
        uint256 shareAmount
    ) public view returns (uint256 vconAmount) {
        uint256 sharePrice = venueLastRecordedVconSharePrice[venue];

        /// if share price is 0, accrueVcon must be called first
        vconAmount = (sharePrice * shareAmount) / Constants.ETH_GRANULARITY;
    }

    /// @param venue to get share price from
    /// @param amountVcon to deposit
    /// return the amount of shares received from depositing into a given venue
    function vconToShares(
        address venue,
        uint256 amountVcon
    ) public view returns (uint256 shareAmount) {
        uint256 sharePrice = venueLastRecordedVconSharePrice[venue];

        shareAmount = (amountVcon * Constants.ETH_GRANULARITY) / sharePrice;
    }

    /// @notice returns the amount of VCON staked in a single venue
    function getVenueVconStaked(address venue) public view returns (uint256) {
        return
            (venueTotalShares[venue] * venueLastRecordedVconSharePrice[venue]) /
            Constants.ETH_GRANULARITY;
    }

    /// get the total amount of VCON staked based on the last cached share prices of each venue
    function getTotalVconStaked()
        public
        view
        returns (uint256 totalVconStaked)
    {
        address[] memory pcvDeposits = pcvOracle().getVenues();
        uint256 totalVenues = pcvDeposits.length;

        for (uint256 i = 0; i < totalVenues; ) {
            address venue = pcvDeposits[i];

            totalVconStaked += getVenueVconStaked(venue);
            unchecked {
                i++;
            }
        }
    }

    /// @notice returns positive value if under allocated
    /// returns negative value if over allocated
    /// if no venue balance and deposited vcon, return positive
    /// if venue balance and no deposited vcon, return negative
    ///
    /// @param venue to query
    /// @param expectedVenueBalance expected venue pcv
    function getVenueDeviation(
        address venue,
        uint256 expectedVenueBalance
    ) public view returns (int256) {
        uint256 venueBalance = pcvOracle().getVenueBalance(venue);

        return venueBalance.toInt256() - expectedVenueBalance.toInt256();
    }

    /// @param venue to figure out total pro rata pcv
    /// @param amountVcon to find total amount of pro rata pcv
    /// @return the pro rata pcv controlled in the given venue based on the amount of VCON
    function getProRataPCVAmounts(
        address venue,
        uint256 amountVcon
    ) public view returns (uint256) {
        uint256 venuePcv = IPCVDeposit(venue).balance();
        uint256 cachedVconStaked = sharesToVcon(venue, venueTotalShares[venue]);

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

    /// @notice return what the perfectly balanced system would look like with all balances normalized to 1e18
    function getExpectedPCVAmounts()
        public
        view
        returns (PCVDepositInfo[] memory deposits)
    {
        address[] memory pcvDeposits = pcvOracle().getVenues();
        uint256 totalVenues = pcvDeposits.length;
        uint256 totalPcv = pcvOracle().getTotalPcv();
        uint256 cachedVconStaked = getTotalVconStaked(); /// Save repeated warm SLOADs

        deposits = new PCVDepositInfo[](totalVenues);

        unchecked {
            for (uint256 i = 0; i < totalVenues; i++) {
                address venue = pcvDeposits[i];
                deposits[i].deposit = venue;
                deposits[i].amount = getExpectedVenuePCVAmount(
                    venue,
                    totalPcv,
                    cachedVconStaked
                );
            }
        }
    }

    function getExpectedVenuePCVAmount(
        address venue,
        uint256 totalPcv,
        uint256 totalVconStaked
    ) public view returns (uint256 expectedPcvAmount) {
        uint256 venueDepositedVcon = sharesToVcon(
            venue,
            venueTotalShares[venue]
        );

        if (totalVconStaked == 0) {
            return 0;
        }

        expectedPcvAmount = (venueDepositedVcon * totalPcv) / totalVconStaked;
    }

    /// ------------- Helper Methods -------------

    /// @param source address to pull funds from
    /// @param destination recipient address for funds
    /// @param swapper address to swap tokens with
    /// @param amountPcv the amount of PCV to move from source
    function _movePCVWithChecks(
        address source,
        address destination,
        address swapper,
        uint256 amountPcv,
        uint256 totalPcv,
        int256 sourceVenueBalance,
        int256 destinationVenueBalance
    ) private {
        address sourceAsset = IPCVDepositV2(source).balanceReportedIn();
        address destinationAsset = IPCVDepositV2(destination)
            .balanceReportedIn();

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

        /// TODO simplify this by passing delta of starting balance
        /// instead of calling balance again on each pcv deposit
        /// record how balanced the system is before the PCV movement
        int256 sourceVenueBalanceAfter = getVenueDeviation(source, totalPcv);
        int256 destinationVenueBalanceAfter = getVenueDeviation(
            destination,
            totalPcv
        );

        /// source and dest venue balance measures the distance from being perfectly balanced

        console.logInt(sourceVenueBalance);
        console.logInt(sourceVenueBalanceAfter);

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

    /// @notice helper function to validate balance moved in the right direction after a pcv movement
    function _checkBalance(
        int256 balanceBefore,
        int256 balanceAfter,
        string memory reason
    ) private pure {
        require(
            balanceBefore < 0 /// if balance is under weight relative to vcon staked, ensure it doesn't go over balance
                ? balanceAfter >= balanceBefore && balanceAfter <= 0 /// if balance is over weight relative to vcon staked, ensure it doesn't go under balance
                : balanceAfter <= balanceBefore && balanceAfter >= 0,
            reason
        );
    }

    /// update the venue last recorded profit
    /// and the venue last recorded vcon share price
    function _accrue(address venue) private {
        /// cache starting recorded profit before the external call even though
        /// there is no way to call _accrue without setting the global reentrancy lock to level 1
        uint256 startingLastRecordedProfit = venueLastRecordedProfit[venue];

        IPCVDepositV2(venue).accrue();

        uint256 endingLastRecordedProfit = IPCVDepositV2(venue)
            .lastRecordedProfit();
        uint256 endingLastRecordedSharePrice = venueLastRecordedVconSharePrice[
            venue
        ];

        /// update venue last recorded profit regardless
        /// of participation in market governance
        if (endingLastRecordedSharePrice != 0) {
            uint256 venueShares = venueTotalShares[venue];
            uint256 venueProfitRatio = profitToVconRatio[venue];

            /// if venue has 0 staked vcon, do not update share price, just update profit index
            if (venueShares != 0) {
                int256 venueProfit = (endingLastRecordedProfit.toInt256() -
                    startingLastRecordedProfit.toInt256());

                int256 vconEarnedPerShare = (Constants.ETH_GRANULARITY_INT *
                    venueProfit *
                    venueProfitRatio.toInt256()) / venueShares.toInt256();

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
