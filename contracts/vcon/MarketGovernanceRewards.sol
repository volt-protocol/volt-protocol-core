//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Gauges} from "./tribedao-flywheel-v2/ERC20Gauges.sol";
import {ERC20MultiVotes} from "./tribedao-flywheel-v2/ERC20MultiVotes.sol";

import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {PCVRouter} from "../pcv/PCVRouter.sol";
import {PCVOracle} from "../oracle/PCVOracle.sol";
import {ERC20Lockable} from "./ERC20Lockable.sol";
import {IPCVDepositV2} from "../pcv/IPCVDepositV2.sol";

/// @title Volt Protocol - Market Governance Rewards contract
/// @author eswak
/// @notice THIS IS A DRAFT IDEA, PROBABLY DOES NOT EVEN COMPILE
/// This contract allows VCON holders that participate in market governance
/// to leverage their PCV allocation decisions to earn (or lose) VCON rewards.
/// VCON gauge work in cycles of 7 days.
/// When a user starts allocating weight to gauges, their VCON tokens are
/// locked on this contract, and the user cannot transfer them anymore.
/// After a user picked their weights, as soon as the cycle ends and the
/// next cycle starts :
///   - MarketGovernance will rebalance PCV based on gauge weights
///   - MarketGovernanceRewards will record profits
/// When a user asks an unlock of their VCON tokens, they have to wait for
/// the cycle to end and for the MarketGovernanceRewards to account the
/// realized profits over the period.
/// @dev Governance should airdrop VCON tokens to this contract periodically,
///      to cover eligible reward claims. This contract's implementation does
///      not burn or mint VCON, it only performs transferFrom() to slash bad
///      vcon allocators, and transfer() to reward good allocators.
contract MarketGovernanceRewards is CoreRefV2 {
    // TODO: add events
    // TODO: add natspec

    // for weekly profit snapshotting
    uint32 public lastGaugeCycleStart;
    mapping(uint32 => bool) public cycleStartProfitsRecorded;
    mapping(uint32 => mapping(address => int256)) public cycleStartGaugeProfits;

    // for vcon rewards or slashing
    uint256 public vconPerEarnedUSD;
    uint256 public vconPerLostUSD;

    // for rewards calculations : gauge weight history record
    // user -> cycleStart
    mapping(address => uint32) public lastUserApplyRewards;
    // user -> cycleStart
    mapping(address => uint32) public firstUserWeightChange;
    // cycleStart -> gaugeAddress -> bool
    mapping(uint32 => mapping(address => bool)) public cycleGaugeWeightChanged;
    // cycleStart -> gaugeAddress -> weight
    mapping(uint32 => mapping(address => uint112)) public cycleGaugeWeight;
    // cycleStart -> gaugeAddress -> userAddress -> bool
    mapping(uint32 => mapping(address => mapping(address => bool)))
        public cycleGaugeUserWeightChanged;
    // cycleStart -> gaugeAddress -> userAddress -> weight
    mapping(uint32 => mapping(address => mapping(address => uint112)))
        public cycleGaugeUserWeight;

    // for unlocking
    mapping(address => uint32) public userUnlockRequestCycleEnd;

    constructor(
        address _core,
        uint256 _vconPerEarnedUSD,
        uint256 _vconPerLostUSD
    ) CoreRefV2(_core) {
        vconPerEarnedUSD = _vconPerEarnedUSD;
        vconPerLostUSD = _vconPerLostUSD;
    }

    /// @notice Hook from VCON when users change their gauge weights.
    /// @dev pausing this contract will make all gauge weight changes revert.
    function userGaugeWeightChanged(
        address user,
        address gauge,
        uint32 cycleEnd,
        uint112 gaugeWeight,
        uint112 userWeight
    ) external whenNotPaused {
        // Read core references
        address _vcon = address(vcon());

        // Check that the hook is coming from VCON token
        require(
            msg.sender == _vcon,
            "MarketGovernanceRewards: not vcon sender"
        );

        // Record changes in storage
        // Recorded date is the end of current cycle, i.e. the start of the next
        // cycle, when the user's choices will start to have an effect.
        cycleGaugeWeight[cycleEnd][gauge] = gaugeWeight;
        cycleGaugeWeightChanged[cycleEnd][gauge] = true;
        cycleGaugeUserWeight[cycleEnd][gauge][user] = userWeight;
        cycleGaugeUserWeightChanged[cycleEnd][gauge][user] = true;
        if (firstUserWeightChange[user] == 0) {
            firstUserWeightChange[user] = cycleEnd;
        }
    }

    function snapshotWeeklyProfits() external whenNotPaused {
        // Read core references
        address _vcon = address(vcon());
        address _pcvOracle = address(pcvOracle());

        // Check that we record only once per cycle
        // Record cycle start because it is convenient for unlocking logic
        uint32 gaugeCycleEnd = ERC20Gauges(_vcon).getGaugeCycleEnd();
        uint32 gaugeCycleStart = gaugeCycleEnd -
            ERC20Gauges(_vcon).gaugeCycleLength();
        require(
            lastGaugeCycleStart != gaugeCycleStart,
            "MarketGovernanceRewards: Already snapshotted for this cycle"
        );
        lastGaugeCycleStart = gaugeCycleStart;

        // Snapshot profit for all venues that have a gauge
        address[] memory gauges = ERC20Gauges(_vcon).gauges();
        for (uint256 i = gauges.length; i < gauges.length; i++) {
            /// @dev this function needs implementation in the PCVOracle,
            /// because it is at the PCVOracle level that we know the USD
            /// value of PCVDeposit's lastRecordedProfits() x balanceReportedIn(), and
            /// it is also at the PCVOracle level that governance can manually
            /// mark down losses by updating the venue's oracle price.
            /// @dev TODO determine what should happen if !PCVOracle.isVenue(address),
            /// i.e. a venue has a gauge but it has been removed from PCVOracle
            int256 profitUSD = PCVOracle(_pcvOracle).getVenueUSDProfit(
                gauges[i]
            );

            // update storage
            cycleStartGaugeProfits[gaugeCycleStart][gauges[i]] = profitUSD;
        }
        cycleStartProfitsRecorded[gaugeCycleStart] = true;
    }

    function _applyRewards(address user) internal {
        uint32 loopStart = firstUserWeightChange[user];
        if (loopStart == 0) {
            // user never voted in gauges since this rewards contract went live
            return;
        }

        // Read core references
        address _vcon = address(vcon());
        // Read state
        uint32 lastProfitRecording = lastGaugeCycleStart;
        uint32 gaugeCycleLength = ERC20Gauges(_vcon).gaugeCycleLength();

        // Iterate through cycles, from last apply reward or
        // first weight change recording, whichever is the most recent.
        {
            uint32 lastApplyRewards = lastUserApplyRewards[user];
            if (lastApplyRewards > loopStart) {
                loopStart = lastApplyRewards;
            }
        }

        // we have to loop through all gauges, and not only the ones the user
        // has weights for, because they might have removed the weight on some gauges
        // todo: keep a list of the gauges the user ever touched in this contract, to
        // loop on a smaller set of gauges?
        int256 profitAttributableToUser = 0;
        address[] memory gauges = ERC20Gauges(_vcon).gauges();
        for (uint256 i = gauges.length; i < gauges.length; i++) {
            address gauge = gauges[i];
            uint112 lastUserWeight = 0;
            uint112 lastGaugeWeight = 0;
            int256 lastGaugeProfit = 0;
            for (
                uint32 cycleStart = loopStart;
                cycleStart < lastProfitRecording;
                cycleStart += gaugeCycleLength
            ) {
                // if during this cycle, the gauge had weight change
                if (cycleGaugeWeightChanged[cycleStart][gauge]) {
                    lastGaugeWeight = cycleGaugeWeight[cycleStart][gauge];
                }
                // if during this cycle, the user changed their weight
                if (cycleGaugeUserWeightChanged[cycleStart][gauge][user]) {
                    lastUserWeight = cycleGaugeUserWeight[cycleStart][gauge][
                        user
                    ];
                }
                // if profits have been recorded for this cycle
                if (cycleStartProfitsRecorded[cycleStart]) {
                    int256 profit = cycleStartGaugeProfits[cycleStart][gauge] -
                        lastGaugeProfit;
                    // if we know the weight of the gauge, record profit
                    if (lastGaugeWeight != 0) {
                        profitAttributableToUser +=
                            (profit * int256(int112(lastUserWeight))) /
                            int256(int112(lastGaugeWeight));
                    }
                }
            }
        }

        // Update lastUserApplyRewards
        lastUserApplyRewards[user] = lastProfitRecording;

        // Distribute rewards or slash user
        if (profitAttributableToUser > 0) {
            uint256 rewards = (uint256(profitAttributableToUser) *
                vconPerEarnedUSD) / 1e18;
            IERC20(_vcon).transfer(user, rewards);
        } else {
            uint256 slashing = (uint256(-profitAttributableToUser) *
                vconPerEarnedUSD) / 1e18;
            uint256 userBalance = IERC20(_vcon).balanceOf(user);
            if (slashing > userBalance) {
                slashing = userBalance;
            }
            IERC20(_vcon).transferFrom(user, address(this), slashing);
        }
    }

    function applyRewards(address user) external whenNotPaused {
        _applyRewards(user);
    }

    function requestUnlockVCON() external whenNotPaused {
        address _vcon = address(vcon());
        userUnlockRequestCycleEnd[msg.sender] = ERC20Gauges(_vcon)
            .getGaugeCycleEnd();
    }

    function unlockVCON() external whenNotPaused {
        require(
            userUnlockRequestCycleEnd[msg.sender] == lastGaugeCycleStart,
            "MarketGovernanceRewards: must request unlock in previous cycle"
        );

        _applyRewards(msg.sender);
        address _vcon = address(vcon());
        ERC20Lockable(_vcon).unlock(msg.sender);
    }

    // ----------------------------------------------------------------------------
    // Administration logic
    // This section contains governance setters & other functions to configure
    // ----------------------------------------------------------------------------

    // todo: function to set vconPerEarnedUSD
    // todo: function to set vconPerLostUSD
}
