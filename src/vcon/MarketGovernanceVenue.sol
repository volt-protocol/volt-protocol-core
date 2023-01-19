pragma solidity =0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {Constants} from "@voltprotocol/Constants.sol";
import {PCVRouter} from "@voltprotocol/pcv/PCVRouter.sol";
import {CoreRefV2} from "@voltprotocol/refs/CoreRefV2.sol";
import {Deviation} from "@test/unit/utils/Deviation.sol";
import {IPCVDepositV2} from "@voltprotocol/pcv/IPCVDepositV2.sol";

contract MarketGovernanceVenue is CoreRefV2 {
    using Deviation for *;
    using SafeERC20 for *;
    using SafeCast for *;

    /// @notice reference to PCV Router
    address public pcvRouter;

    /// @notice amount of VCON paid per unit of revenue generated
    uint256 public profitToVconRatio;

    /// @notice total amount of VCON deposited across all venues
    uint256 public totalSupply;

    /// TODO simplify this contract down to only track venue profit,
    /// and do the conversion to VCON at the end when accruing rewards

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

    /// ---------- Per Venue User Profit Tracking ----------

    /// @notice approved routes to swap different tokens and their corresponding swapper address
    /// first address is token from, second address is tokenTo, third address is corresponding swapper
    /// the starting approved routes will be DAI -> USDC and USDC -> DAI through the Maker PCV Swapper
    mapping(address => mapping(address => address)) public approvedRoutes;

    /// @param _core reference to core
    /// @param _pcvRouter reference to the PCV Router
    /// @param _profitToVconRatio ratio of VCON paid out per dollar in revenue
    constructor(
        address _core,
        address _pcvRouter,
        uint256 _profitToVconRatio
    ) CoreRefV2(_core) {
        pcvRouter = _pcvRouter;
        profitToVconRatio = _profitToVconRatio;
    }

    /// TODO update pcv oracle to cache total pcv so getAllPCV isn't needed to figure
    /// out if weights are correct
    /// TODO change movePCV to use a different global reentrancy lock state, or require system be lock level 1 to use that function
    /// @param source address to pull funds from
    /// @param destination address to accrue rewards to, and send funds to
    function deposit(
        uint256 amountVcon,
        uint256 amountPcv,
        address source,
        address destination
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

        _movePcv(source, destination, amountPcv);
    }

    /// @notice unstake VCON and transfer corresponding VCON to another venue
    /// @param amountVcon the amount of VCON staked to unstake
    /// @param source address to accrue rewards to, and pull funds from
    function withdraw(
        uint256 amountVcon,
        uint256 amountPcv,
        address source,
        address destination,
        address vconRecipient
    ) external globalLock(1) {
        require(source != destination, "MarketGovernance: src and dest equal");

        _accrue(source); /// update profitPerVCON in the source so the user gets paid out at the current share price
        {
            uint256 vconRewards = _harvestRewards(msg.sender, source); /// pay msg.sender their rewards

            require(
                userVenueDepositedVcon[source][msg.sender] + vconRewards >=
                    amountVcon,
                "MarketGovernance: invalid vcon amount"
            );

            /// check and an interaction with a trusted contract

            vcon().safeTransfer(vconRecipient, amountVcon); /// transfer VCON to recipient

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

        _movePcv(source, destination, amountPcv);
    }

    /// @notice rebalance PCV without staking or unstaking VCON
    function rebalance(
        address source,
        address destination,
        uint256 amountPcv
    ) external globalLock(1) {
        _movePcv(source, destination, amountPcv);
    }

    function _movePcv(
        address source,
        address destination,
        uint256 amountPcv
    ) private {
        address sourceAsset = IPCVDepositV2(source).balanceReportedIn();
        address destinationAsset = IPCVDepositV2(destination)
            .balanceReportedIn();
        address swapper = approvedRoutes[sourceAsset][destinationAsset];

        /// TODO fix this method on the oracle because it doesn't allow the read while in lock mode
        uint256 totalPcv = pcvOracle().getTotalPcv();

        /// record how balanced the system is before the PCV movement
        int256 sourceVenueBalance = getVenueBalance(source, totalPcv);
        int256 destinationVenueBalance = getVenueBalance(destination, totalPcv);

        /// optimistically transfer funds to the specified pcv deposit
        /// swapper validity not checked in this contract as the PCV Router will check this
        PCVRouter(pcvRouter).movePCV(
            source,
            destination,
            swapper,
            amountPcv,
            sourceAsset,
            destinationAsset
        );

        /// TODO simplify this by passing delta of starting balance instead of calling balance again on each pcv deposit
        /// record how balanced the system is before the PCV movement
        int256 sourceVenueBalanceAfter = getVenueBalance(source, totalPcv);
        int256 destinationVenueBalanceAfter = getVenueBalance(
            destination,
            totalPcv
        );

        /// source and dest venue balance measures the distance from being perfectly balanced
        /// validate source venue balance became more balanced
        require(
            sourceVenueBalance < 0 /// if balance is under weight relative to vcon staked, ensure it doesn't go over balance
                ? sourceVenueBalanceAfter > sourceVenueBalance &&
                    sourceVenueBalanceAfter <= 0 /// if balance is over weight relative to vcon staked, ensure it doesn't go under balance
                : sourceVenueBalanceAfter < sourceVenueBalance &&
                    sourceVenueBalanceAfter >= 0,
            "MarketGovernance: src more imbalanced"
        );

        /// validate destination venue balance became more balanced
        require(
            destinationVenueBalance < 0 /// if balance is under weight relative to vcon staked, ensure it doesn't go over balance
                ? destinationVenueBalanceAfter > destinationVenueBalance &&
                    destinationVenueBalanceAfter <= 0 /// if balance is over weight relative to vcon staked, ensure it doesn't go under balance
                : destinationVenueBalanceAfter > destinationVenueBalance &&
                    destinationVenueBalanceAfter >= 0,
            "MarketGovernance: src more imbalanced"
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
        int256 profitPerVconDelta = (deltaProfit *
            profitToVconRatio.toInt256()) / totalSupply.toInt256();

        lastRecordedVconPricePerVenue[venue] = (lastRecordedVconPricePerVenue[
            venue
        ].toInt256() + profitPerVconDelta).toUint256().toUint128();
    }

    /// @notice returns positive value if over allocated
    /// returns negative value if under allocated
    function getVenueBalance(
        address venue,
        uint256 totalPcv
    ) public view returns (int256) {
        uint256 venueDepositedVcon = totalVenueDepositedVcon[venue];

        uint256 venueBalance = pcvOracle().getVenueBalance(venue);

        if (venueDepositedVcon == 0 && venueBalance == 0) {
            return 0; /// perfectly balanced at 0 PCV
        }

        /// if no venue balance and deposited vcon, return positive
        /// if venue balance and no deposited vcon, return negative

        /// find out the actual ratio of PCV in a given venue based on PCV
        uint256 venueRatio = (venueBalance * Constants.ETH_GRANULARITY) /
            totalPcv;

        /// find out expected ratio of PCV in a given venue based on VCON staked
        uint256 venueDepositedVconRatio = (venueDepositedVcon *
            Constants.ETH_GRANULARITY) / totalSupply;

        /// if no venue deposited vcon, we would divide by 0, and revert, so reverse order and multiply by -1
        /// this means there is too much PCV for the amount of VCON in the venue
        if (venueDepositedVconRatio == 0) {
            return
                -1 *
                Deviation.calculateDeviationBasisPoints(
                    venueRatio.toInt256(),
                    venueDepositedVconRatio.toInt256()
                );
        }

        /// if venue deposited VCON, return the regular ratio between vcon deposited and pcv deposited
        return
            Deviation.calculateDeviationBasisPoints(
                venueDepositedVconRatio.toInt256(),
                venueRatio.toInt256()
            );
    }

    /// TODO add governance API's to change the pcv router
    /// profitToVconRatio
    /// approved routes
    /// TODO add events
}
