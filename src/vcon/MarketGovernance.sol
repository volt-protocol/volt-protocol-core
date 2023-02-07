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

/// TODO cache pcv oracle total pcv so getAllPCV isn't needed to figure
/// out total pcv

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
///     ∆Share Price = (Ending Share Price - Starting Share Price)
///     User VCON rewards = ∆Share Price * User Shares
///
/// Anytime the rewards share price changes, so does the unclaimed user VCON rewards.
///
/// @dev users can stake on PCV deposits that are not productive, such as the holding deposit,
/// however, they will receive no rewards for doing so if the profit to VCON ratio is not set.
/// The PSM will not be able to be staked on as it is not whitelisted in the PCV Oracle.
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

    /// @notice map an underlying token to the corresponding holding deposit
    mapping(address => address) public underlyingTokenToHoldingDeposit;

    /// no balance checks when unstaking

    /// ---------- Per Venue User Profit Tracking ----------

    /// @dev convention for all double nested address mappings is key (venue -> user) -> value

    /// @notice record how much VCON a user deposited in a given venue
    mapping(address => mapping(address => uint256)) public venueUserShares;

    /// @param _core reference to core
    /// @param _pcvRouter reference to pcvRouter
    constructor(address _core, address _pcvRouter) CoreRefV2(_core) {
        pcvRouter = _pcvRouter;
    }

    /// @notice update the VCON share price and the last recorded profit for a given venue
    /// @param venue address to accrue
    function accrueVcon(address venue) external globalLock(1) whenNotPaused {
        IPCVOracle oracle = pcvOracle();

        require(oracle.isVenue(venue), "MarketGovernance: invalid destination");

        _accrue(venue);
    }

    /// ---------- Permissionless User PCV Allocation Methods ----------

    /// @notice a user can get slashed up to their full VCON stake for entering
    /// a venue that takes a loss.
    /// @param amountVcon to stake on destination
    /// @param venue address to accrue rewards to, and send funds to
    function stake(
        uint256 amountVcon,
        address venue
    ) external globalLock(1) whenNotPaused {
        IPCVOracle oracle = pcvOracle();
        require(oracle.isVenue(venue), "MarketGovernance: invalid destination");

        _accrue(venue); /// update share price in the destination so the user gets in at the current share price

        /// vconToShares will always return correctly as accrue will set venueLastRecordedVconSharePrice
        /// to the correct share price from 0 if uninitialized
        uint256 userShareAmount = vconToShares(venue, amountVcon);

        /// user updates
        venueUserShares[venue][msg.sender] += userShareAmount;

        /// venue updates
        venueTotalShares[venue] += userShareAmount;

        /// check and an interaction with a trusted contract
        vcon().safeTransferFrom(msg.sender, address(this), amountVcon); /// transfer VCON in

        emit Staked(venue, msg.sender, amountVcon);
    }

    /// @notice unstake VCON and transfer corresponding VCON to another venue
    /// @param shareAmount the amount of shares to unstake
    /// @param venue address to accrue rewards to, and pull funds from
    /// @param vconRecipient address to receive the VCON
    /// @dev both venue and destination are checked twice,
    /// the first time in the market governance contract,
    /// the second time in the PCV Router contract.
    function unstake(
        uint256 shareAmount,
        address venue,
        address vconRecipient
    ) external globalLock(1) whenNotPaused {
        /// ---------- Checks ----------
        IPCVOracle oracle = pcvOracle();

        require(oracle.isVenue(venue), "MarketGovernance: invalid venue");
        require(
            venueUserShares[venue][msg.sender] >= shareAmount,
            "MarketGovernance: invalid share amount"
        );

        address denomination = IPCVDepositV2(venue).balanceReportedIn();
        address destination = underlyingTokenToHoldingDeposit[denomination];
        require(
            destination != address(0),
            "MarketGovernance: invalid destination"
        );

        /// ---------- Effects ----------

        _accrue(venue); /// update profitPerVCON in the venue so the user gets paid out at the current share price

        /// figure out how balanced the system is before withdraw

        /// amount of PCV to withdraw is the amount vcon * venue balance / total vcon staked on venue
        uint256 amountPcv = getProRataPCVAmounts(venue, shareAmount);

        /// user updates
        venueUserShares[venue][msg.sender] -= shareAmount;

        /// venue updates
        venueTotalShares[venue] -= shareAmount;

        /// ---------- Interactions ----------

        {
            PCVRouter(pcvRouter).movePCV(
                venue,
                destination,
                address(0),
                amountPcv,
                denomination,
                denomination
            );
        }

        {
            uint256 amountVcon = sharesToVcon(venue, shareAmount);
            vcon().safeTransfer(vconRecipient, amountVcon); /// transfer VCON amount to recipient
            emit Unstaked(venue, msg.sender, amountVcon, amountPcv);
        }
    }

    /// @notice rebalance PCV without staking or unstaking VCON
    /// each individual action must make the system more balanced
    /// as a whole, otherwise it will revert
    /// @param movements information on all pcv movements
    /// including sources, destinations, amounts and swappers
    function rebalance(
        Rebalance[] calldata movements
    ) external globalLock(1) whenNotPaused {
        /// read unsafe because we are at lock level 1
        IPCVOracle oracle = pcvOracle();
        uint256 totalPcv = oracle.getTotalPcv();
        uint256 totalVconStaked = getTotalVconStaked();
        unchecked {
            for (uint256 i = 0; i < movements.length; i++) {
                address source = movements[i].source;
                address destination = movements[i].destination;
                address swapper = movements[i].swapper;
                uint256 amountPcv = movements[i].amountPcv;

                /// validate source, dest and swapper
                require(
                    oracle.isVenue(source),
                    "MarketGovernance: invalid source"
                );
                require(
                    oracle.isVenue(destination),
                    "MarketGovernance: invalid destination"
                );
                /// if swapper is used, validate in PCV Router whiteliste
                if (swapper != address(0)) {
                    require(
                        PCVRouter(pcvRouter).isPCVSwapper(swapper),
                        "MarketGovernance: invalid swapper"
                    );
                }

                /// call accrue on destination to ensure no unrealized losses have occured
                _accrue(destination);

                /// record how balanced the system is before the PCV movement
                int256 sourceVenueBalance = getVenueDeviation(
                    source,
                    totalPcv,
                    totalVconStaked
                );
                int256 destinationVenueBalance = getVenueDeviation(
                    destination,
                    totalPcv,
                    totalVconStaked
                );

                _movePCVWithChecks(
                    source,
                    destination,
                    swapper,
                    amountPcv,
                    totalPcv,
                    sourceVenueBalance,
                    destinationVenueBalance,
                    totalVconStaked
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
    /// during a loss scenario, this function will return an incorrect total amount of VCON staked
    /// because the share price in the venues have not been marked down, leading to an incorrect sum.
    /// all functions that call this function during a loss scenario will also be incorrect
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

    /// @notice returns positive value if over allocated
    /// returns negative value if under allocated
    /// if no venue balance and deposited vcon, return positive
    /// if venue balance and no deposited vcon, return negative
    ///
    /// @param venue to query
    /// @param totalPcv expected venue pcv
    /// @param totalVconStaked expected venue pcv
    function getVenueDeviation(
        address venue,
        uint256 totalPcv,
        uint256 totalVconStaked
    ) public view returns (int256) {
        uint256 venueBalance = pcvOracle().getVenueBalance(venue); /// decimal normalized balance
        uint256 expectedVenueBalance = getExpectedVenuePCVAmount(
            venue,
            totalPcv,
            totalVconStaked
        );

        return venueBalance.toInt256() - expectedVenueBalance.toInt256();
    }

    /// @param venue to figure out total pro rata pcv
    /// @param shareAmount to find total amount of pro rata pcv
    /// @return the pro rata pcv controlled in the given venue based on the amount of shares
    /// returned amount will be used to call the PCV router, so return a non-decimal normalized value
    function getProRataPCVAmounts(
        address venue,
        uint256 shareAmount
    ) public view returns (uint256) {
        uint256 venuePcv = IPCVDepositV2(venue).balance();
        uint256 cachedTotalShares = venueTotalShares[venue]; /// save a single warm SLOAD

        /// 0 checks as any 0 denominator will cause a revert
        if (cachedTotalShares == 0) {
            return 0;
        }

        /// @audit we do not add 1 to the pro rata PCV here. This means a withdrawal of 1 Wei of shares
        /// will allow removing a user's VCON without having to withdraw PCV from a venue.
        /// This is a known issue, however it is not harmful as it would require a quintillion withdrawals
        /// to withdraw 1 VCON, which would cost at minimum 5,000e18 gas per withdraw, meaning it would cost at least 1 million ether
        /// (likely more) to retrieve a single VCON without moving PCV.
        /// The only reason this would ever get expoited is if a loss was taken and a user was trying to avoid realizing their portion
        /// of the losses. However, in a loss scenario, the unstake function does not allow execution if the user has an unrealized
        /// loss in that venue. This condition stops the aforementioned exploit.
        /// fix would require rounding up in the protocol's favor, so that a withdrawal of 1 Wei of VCON has an actual withdraw amount
        uint256 proRataPcv = (shareAmount * venuePcv) / cachedTotalShares;

        return proRataPcv;
    }

    /// @dev algorithm to find all rebalance actions necessary to get system to fully balanced
    /// get expected PCV amounts in each venue
    /// build out 2 ordered arrays
    /// 1 of deposits underweight with most underweight placed first
    /// 2 of deposits overweight with most overweight placed first
    /// create an array of actions
    /// iterate through list 2, starting at item 0, then iterate over list 1, making an action
    /// pulling funds from this venue either till exhausted, or until item in list one is filled
    /// if list 1 item filled, iterate to next item in list 1
    /// if list 1 item unfilled and list 2 item perfectly balanced, go to next item in list 2
    /// iterate over array of actions and correct decimals if swapping between USDC and DAI

    /// @notice return what the perfectly balanced system would look like with all balances normalized to 1e18
    function getExpectedPCVAmounts()
        external
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
        int256 destinationVenueBalance,
        uint256 totalVconStaked
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

        /// if nothing is staked on source, ignore balance check
        if (sharesToVcon(source, venueTotalShares[source]) > 0) {
            int256 sourceVenueBalanceAfter = getVenueDeviation(
                source,
                totalPcv,
                totalVconStaked
            );

            /// source and dest venue balance measures the distance from being perfectly balanced

            /// validate source venue balance became more balanced
            _checkBalance(
                sourceVenueBalance,
                sourceVenueBalanceAfter,
                "MarketGovernance: src more imbalanced"
            );
        }

        int256 destinationVenueBalanceAfter = getVenueDeviation(
            destination,
            totalPcv,
            totalVconStaked
        );

        /// validate destination venue balance became more balanced
        _checkBalance(
            destinationVenueBalance,
            destinationVenueBalanceAfter,
            "MarketGovernance: dest more imbalanced"
        );
    }

    /// @notice helper function to validate balance moved in the right direction after a pcv movement
    /// if balance before and after are the same, return true
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

    /// @notice update the venue last recorded profit
    /// and the venue last recorded vcon share price
    /// system must be at lock level 1 to call this function,
    /// otherwise call to `accrue()` on the PCV Deposit will fail
    /// @dev this function assumes the venue is in the PCV Oracle as the
    /// calling function should either check, or be callable only by
    /// governance
    function _accrue(address venue) private {
        /// cache starting recorded profit before the external call even though
        /// there is no way to call _accrue without setting the global reentrancy lock to level 1
        uint256 startingLastRecordedProfit = venueLastRecordedProfit[venue];

        IPCVDepositV2(venue).accrue();

        uint256 lastRecordedProfit = IPCVDepositV2(venue).lastRecordedProfit(); /// get this from the pcv oracle as it will be decimal normalized
        uint256 endingLastRecordedSharePrice = venueLastRecordedVconSharePrice[
            venue
        ];
        int256 venueProfit = (lastRecordedProfit.toInt256() -
            startingLastRecordedProfit.toInt256());

        require(venueProfit >= 0, "MarketGovernance: loss scenario");

        /// update venue last recorded profit regardless
        /// of participation in market governance
        if (endingLastRecordedSharePrice != 0) {
            uint256 venueShares = venueTotalShares[venue];

            /// if venue has 0 staked vcon, do not update share price, just update profit index
            if (venueShares != 0) {
                uint256 venueProfitRatio = profitToVconRatio[venue];

                uint256 vconEarnedPerShare = (Constants.ETH_GRANULARITY *
                    venueProfit.toUint256() *
                    venueProfitRatio) / venueShares;

                /// gain scenario
                venueLastRecordedVconSharePrice[venue] += vconEarnedPerShare
                    .toUint128();
            }
        } else {
            /// share price is 0, and requires initialization
            venueLastRecordedVconSharePrice[venue] = Constants
                .ETH_GRANULARITY
                .toUint128();
        }

        /// update the venue's profit index
        venueLastRecordedProfit[venue] = lastRecordedProfit.toUint128();

        emit VenueIndexUpdated(venue, block.timestamp, lastRecordedProfit);
    }

    /// ---------- Governor-Only Permissioned API ----------

    /// @notice governor only function to set the profit to VCON ratio
    /// this function will not be callable if an underlying venue took a loss as `_accrue()`
    /// will revert and no users will be able to withdraw their VCON.
    function setProfitToVconRatio(
        address venue,
        uint256 newProfitToVconRatio
    ) external onlyGovernor globalLock(1) {
        /// lock to level 1 so that accrue can succeed
        require(pcvOracle().isVenue(venue), "MarketGovernance: invalid venue");
        _accrue(venue); /// ensure users receive all rewards from the old rate

        uint256 oldProfitToVconRatio = profitToVconRatio[venue];
        profitToVconRatio[venue] = newProfitToVconRatio;

        emit ProfitToVconRatioUpdated(
            venue,
            oldProfitToVconRatio,
            newProfitToVconRatio
        );
    }

    /// @notice governor only function to set the PCV Router for market governance rebalances
    function setPCVRouter(address newPcvRouter) external onlyGovernor {
        address oldPcvRouter = pcvRouter;
        pcvRouter = newPcvRouter;

        emit PCVRouterUpdated(oldPcvRouter, newPcvRouter);
    }

    /// @notice governor only function to set a venue for market governance withdrawals in a given denomination
    /// @param token underlying token for venue to handle
    /// @param venue where funds of denomination `token` will be withdrawn to
    /// @dev venue must be a whitelisted PCV Deposit,
    /// and the venue's underlying token must match the token passed
    function setUnderlyingTokenHoldingDeposit(
        address token,
        address venue
    ) external onlyGovernor {
        require(pcvOracle().isVenue(venue), "MarketGovernance: invalid venue");
        require(
            IPCVDepositV2(venue).balanceReportedIn() == token,
            "MarketGovernance: underlying mismatch"
        );

        underlyingTokenToHoldingDeposit[token] = venue;

        emit UnderlyingTokenDepositUpdated(token, venue);
    }

    /// Governor applies losses to a venue
    /// @param venue address of venue to apply losses to
    /// @param newSharePrice new share price
    function applyVenueLosses(
        address venue,
        uint128 newSharePrice
    ) external onlyGovernor globalLock(1) {
        require(pcvOracle().isVenue(venue), "MarketGovernance: invalid venue");

        uint256 oldSharePrice = venueLastRecordedVconSharePrice[venue];

        /// setting to 0 would cause re-initialization in accrue function, nullifying these changes
        require(
            newSharePrice != 0,
            "MarketGovernance: cannot set share price to 0"
        );

        /// cannot apply a gain to the share price, only losses
        require(
            newSharePrice < oldSharePrice,
            "MarketGovernance: share price not less"
        );

        IPCVDepositV2(venue).accrue();

        uint256 lastRecordedProfit = IPCVDepositV2(venue).lastRecordedProfit();

        /// update the venue's profit index
        venueLastRecordedProfit[venue] = lastRecordedProfit.toUint128();
        /// update the venue's share price
        venueLastRecordedVconSharePrice[venue] = newSharePrice;

        emit LossesApplied(venue, oldSharePrice, newSharePrice);
    }
}
