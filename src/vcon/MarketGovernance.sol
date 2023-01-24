// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {PCVMover} from "@voltprotocol/pcv/PCVMover.sol";
import {Constants} from "@voltprotocol/Constants.sol";
import {CoreRefV2} from "@voltprotocol/refs/CoreRefV2.sol";
import {Deviation} from "@test/unit/utils/Deviation.sol";
import {IPCVDepositV2} from "@voltprotocol/pcv/IPCVDepositV2.sol";

import {console} from "@forge-std/console.sol";

/// @notice this contract requires the PCV Controller and Locker role
/// Core formula for market governance rewards:
///     Profit Per VCON = Profit Per VCON + ∆Cumulative Profits (Dollars) * VCON:Dollar  / VCON Staked
contract MarketGovernance is CoreRefV2, PCVMover {
    using Deviation for *;
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
    uint256 public totalSupply;

    /// @dev convention for all normal mappings is key (venue -> value)

    /// @notice amount of VCON paid per unit of revenue generated per venue
    /// different venues may have different ratios to account for rewards
    /// which will not be included in the V1
    mapping(address => uint256) public profitToVconRatio;

    /// TODO simplify this contract down to only track venue profit,
    /// and do the conversion to VCON at the end when accruing rewards
    /// alternatively, pack lastRecordedVconPricePerVenue,
    /// lastRecordedProfit and totalVenueDepositedVcon into a single slot for gas optimization

    /// @notice last recorded profit index per venue
    mapping(address => uint128) public lastRecordedProfit;

    /// @notice last recorded share price of a venue in VCON
    /// starts off at 1e18
    mapping(address => uint128) public lastRecordedVconPricePerVenue;

    /// @notice total vcon deposited per venue
    mapping(address => uint256) public totalVenueDepositedVcon;

    /// ---------- Per Venue User Profit Tracking ----------

    /// @dev convention for all double nested address mappings is key (venue -> user) -> value

    /// @notice record of VCON index when user joined a given venue
    mapping(address => mapping(address => uint256))
        public startingVenueVconProfit;

    /// @notice record how much VCON a user deposited in a given venue
    mapping(address => mapping(address => uint256))
        public userVenueDepositedVcon;

    /// @param _core reference to core
    constructor(address _core) CoreRefV2(_core) {}

    /// @notice permissionlessly initialize a venue
    /// required to be able to utilize a given PCV Deposit in market governance
    function initializeVenue(address venue) external globalLock(1) {
        require(pcvOracle().isVenue(venue), "MarketGovernance: invalid venue");

        uint256 startingLastRecordedProfit = lastRecordedProfit[venue];
        require(
            startingLastRecordedProfit == 0,
            "MarketGovernance: profit already recorded"
        );
        require(
            lastRecordedVconPricePerVenue[venue] == 0,
            "MarketGovernance: venue already has share price"
        );

        IPCVDepositV2(venue).accrue();

        uint256 endingLastRecordedProfit = IPCVDepositV2(venue)
            .lastRecordedProfit();

        lastRecordedProfit[venue] = endingLastRecordedProfit.toUint128();
        lastRecordedVconPricePerVenue[venue] = Constants
            .ETH_GRANULARITY
            .toUint128();
    }

    /// ---------- Permissionless User PCV Allocation Methods ----------

    /// TODO update pcv oracle to cache total pcv so getAllPCV isn't needed to figure
    /// out if weights are correct
    /// @param amountVcon to stake on destination
    /// @param amountPcv to move from source to destination
    /// @param source address to pull funds from
    /// @param destination address to accrue rewards to, and send funds to
    /// @param swapper address that swaps asset types between src and dest if needed
    function deposit(
        uint256 amountVcon,
        uint256 amountPcv,
        address source,
        address destination,
        address swapper
    ) external globalLock(1) {
        _accrue(destination); /// update profitPerVCON in the destination so the user gets in at the current share price
        uint256 vconRewards = _harvestRewards(msg.sender, destination); /// auto-compound rewards
        /// check and an interaction with a trusted contract
        vcon().safeTransferFrom(msg.sender, address(this), amountVcon); /// transfer VCON in

        uint256 totalVconDeposited = amountVcon + vconRewards; /// auto-compound rewards

        /// global updates
        totalSupply += totalVconDeposited;

        /// user updates
        userVenueDepositedVcon[destination][msg.sender] += totalVconDeposited;

        /// venue updates
        totalVenueDepositedVcon[destination] += totalVconDeposited;

        /// ignore balance checks if only one user is allocating in the system
        bool ignoreBalanceChecks = totalSupply == totalVconDeposited;

        _movePCVWithChecks(
            source,
            destination,
            swapper,
            amountPcv,
            ignoreBalanceChecks
        );
    }

    /// @notice deposit VCON without moving PCV
    /// @param venue to stake VCON on
    /// @param amountVcon amount of VCON to stake
    function depositNoMove(
        address venue,
        uint256 amountVcon
    ) external globalLock(1) {
        /// update profitPerVCON in the destination so the user buys
        /// in at the current share price
        /// interaction, unfortunately it is necessary to do this before updating the user's balance
        /// in order to ensure the user gets the current venue price when they stake
        _accrue(venue);

        uint256 vconRewards = _harvestRewards(msg.sender, venue); /// auto-compound rewards

        uint256 totalVconDeposited = amountVcon + vconRewards; /// auto-compound rewards

        /// effects

        /// global updates
        totalSupply += totalVconDeposited;

        /// user updates
        userVenueDepositedVcon[venue][msg.sender] += totalVconDeposited;

        /// venue updates
        totalVenueDepositedVcon[venue] += totalVconDeposited;

        /// interactions

        /// check and an interaction with a trusted contract
        vcon().safeTransferFrom(msg.sender, address(this), amountVcon); /// transfer VCON in
    }

    /// TODO add a function that decouples the movement of PCV from the
    /// depositing so users can deposit without paying huge gas costs

    /// @notice unstake VCON and transfer corresponding VCON to another venue
    /// @param amountVcon the amount of VCON staked to unstake
    /// @param amountPcv the amount of PCV to move from source
    /// @param source address to accrue rewards to, and pull funds from
    /// @param destination address to send funds
    /// @param vconRecipient address to receive the VCON
    function withdraw(
        uint256 amountVcon,
        uint256 amountPcv,
        address source,
        address destination,
        address swapper,
        address vconRecipient
    ) external globalLock(1) {
        /// ---------- Check ----------

        require(source != destination, "MarketGovernance: src and dest equal");

        /// ---------- Effects ----------

        _accrue(source); /// update profitPerVCON in the source so the user gets paid out at the current share price
        {
            uint256 vconRewards = _harvestRewards(msg.sender, source); /// pay msg.sender their rewards

            require(
                userVenueDepositedVcon[source][msg.sender] + vconRewards >=
                    amountVcon,
                "MarketGovernance: invalid vcon amount"
            );

            /// global updates
            totalSupply -= amountVcon;

            /// user updates
            /// balance = 80
            /// amount = 100
            /// rewards = 30
            /// amount deducted = 70
            /// _____________
            /// balance = 10
            userVenueDepositedVcon[source][msg.sender] -=
                amountVcon -
                vconRewards;
        }

        /// venue updates
        totalVenueDepositedVcon[destination] -= amountVcon;

        /// ---------- Interactions ----------

        vcon().safeTransfer(vconRecipient, amountVcon); /// transfer VCON to recipient

        /// ignore balance checks if only one user is allocating in the system
        bool ignoreBalanceChecks = totalSupply ==
            userVenueDepositedVcon[source][msg.sender];

        _movePCVWithChecks(
            source,
            destination,
            swapper,
            amountPcv,
            ignoreBalanceChecks
        );
    }

    /// @notice rebalance PCV without staking or unstaking VCON
    /// @param source address to pull funds from
    /// @param destination recipient address for funds
    /// @param swapper address that swaps denominations if necessary
    /// @param amountPcv the amount of PCV to move from source
    function rebalance(
        address source,
        address destination,
        address swapper,
        uint256 amountPcv
    ) external globalLock(1) {
        _movePCVWithChecks(source, destination, swapper, amountPcv, false);
    }

    struct Rebalance {
        address source;
        address destination;
        address swapper;
        uint256 amountPcv;
    }

    /// @notice rebalance PCV without staking or unstaking VCON
    /// each individual action must make the system more balanced
    /// as a whole, otherwise it will revert
    /// @param movements information on all pcv movements
    /// including sources, destinations, amounts and swappers
    function rebalanceBulk(
        Rebalance[] calldata movements
    ) external globalLock(1) {
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
        uint256 venueDepositedVcon = totalVenueDepositedVcon[venue];
        uint256 venueBalance = pcvOracle().getVenueBalance(venue);
        uint256 cachedTotalSupply = totalSupply;

        /// 0 checks as any 0 denominator will cause a revert
        if (
            (venueDepositedVcon == 0 && venueBalance == 0) ||
            cachedTotalSupply == 0 ||
            totalPcv == 0
        ) {
            return 0; /// perfectly balanced at 0 PCV or 0 VCON staked
        }

        /// Step 1.
        /// find out actual ratio of VCON in a given venue based on total VCON staked
        uint256 venueDepositedVconRatio = (venueDepositedVcon *
            Constants.ETH_GRANULARITY) / cachedTotalSupply;

        /// perfectly balanced
        if (venueDepositedVconRatio == 0 && venueBalance == 0) {
            return 0;
        }

        if (venueDepositedVconRatio == 0) {
            /// add this 0 check because deviation divides by a and would cause a revert
            /// replicate step 3 if no VCON is deposited by comparing pcv to venue balance
            return
                Deviation.calculateDeviationEthGranularity(
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
            -Deviation.calculateDeviationEthGranularity(
                expectedPcvAmount.toInt256(),
                venueBalance.toInt256()
            );
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
        uint256 cachedTotalSupply = totalSupply; /// Save repeated warm SLOADs

        deposits = new PCVDepositInfo[](totalVenues);

        unchecked {
            for (uint256 i = 0; i < totalVenues; i++) {
                address venue = pcvDeposits[i];
                uint256 venueDepositedVcon = totalVenueDepositedVcon[venue];
                deposits[i].deposit = venue;

                if (venueDepositedVcon == 0) {
                    deposits[i].amount = 0;
                    continue;
                } else {
                    uint256 expectedPcvAmount = (venueDepositedVcon *
                        totalPcv) / cachedTotalSupply;

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

    /// @notice returns profit in VCON a user has accrued
    /// does not update how much VCON a user has staked to save on gas
    /// that updating happens in the calling function
    function _harvestRewards(
        address user,
        address venue
    ) private returns (uint256) {
        uint256 vconStartIndex = startingVenueVconProfit[venue][user];
        uint256 vconCurrentIndex = lastRecordedVconPricePerVenue[venue];

        /// do not pay out if user has not entered the market
        if (vconStartIndex == 0) {
            /// set user starting profit to current venue profit index
            startingVenueVconProfit[venue][user] = vconCurrentIndex;
            return 0; /// no profits
        }

        uint256 vconRewards = (vconCurrentIndex - vconStartIndex) *
            userVenueDepositedVcon[venue][user];
        startingVenueVconProfit[venue][user] = vconCurrentIndex;

        return vconRewards;
    }

    function _accrue(address venue) private {
        uint256 startingLastRecordedProfit = lastRecordedProfit[venue];

        IPCVDepositV2(venue).accrue();

        uint256 endingLastRecordedProfit = IPCVDepositV2(venue)
            .lastRecordedProfit();
        int256 deltaProfit = endingLastRecordedProfit.toInt256() -
            startingLastRecordedProfit.toInt256(); /// also could be a loss

        /// amount of VCON that each VCON deposit receives for being in this venue
        /// if there is no supply, there is no delta to apply
        if (totalSupply != 0) {
            int256 venueProfitToVconRatio = profitToVconRatio[venue].toInt256();

            int256 profitPerVconDelta = (deltaProfit * venueProfitToVconRatio) /
                totalSupply.toInt256();

            uint256 lastVconSharePrice = lastRecordedVconPricePerVenue[venue];
            require(
                lastVconSharePrice >= Constants.ETH_GRANULARITY,
                "MarketGovernance: venue not initialized"
            );

            lastRecordedVconPricePerVenue[venue] = (lastVconSharePrice
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
