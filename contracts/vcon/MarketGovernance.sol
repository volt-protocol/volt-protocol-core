//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Gauges} from "../vcon/tribedao-flywheel-v2/ERC20Gauges.sol";

import {CoreRefV2} from "../refs/CoreRefV2.sol";
import {PCVRouter} from "../pcv/PCVRouter.sol";
import {PCVOracle} from "../oracle/PCVOracle.sol";
import {IPCVDepositV2} from "../pcv/IPCVDepositV2.sol";

/// @title Volt Protocol - Market Governance contract
/// @author eswak
/// @notice This contract allows VCON holders to decide, through gauge voting,
/// how the PCV backing VOLT is allocated among a list of venues.
/// Every gauge cycle, this contract will read gauge weights and allow for a
/// rebalancing of the PCV among venues that have a gauge, using the PCVRouter.
contract MarketGovernance is CoreRefV2 {
    // TODO: add events
    // TODO: add natspec

    uint32 public lastGaugeCycleEnd;
    address public pcvRouter;

    constructor(address _core, address _pcvRouter) CoreRefV2(_core) {
        pcvRouter = _pcvRouter;
    }

    struct PCVMovement {
        address venueFrom;
        address venueTo;
        address swapper;
        uint256 amount;
        address sourceAsset;
        address destinationAsset;
        bool sourceIsLiquid;
        bool destinationIsLiquid;
    }

    function canRebalance() external view returns (bool) {
        address _vcon = address(vcon());
        uint32 gaugeCycleEnd = ERC20Gauges(_vcon).getGaugeCycleEnd();
        if (lastGaugeCycleEnd == gaugeCycleEnd) {
            return false; // already rebalanced this cycle
        } else if (paused()) {
            return false; // contract is paused (all CoreRefs are pausable)
        } else {
            return true;
        }
    }

    /// @notice rebalance PCV between venues, based on VCON gauge votings.
    /// Can only be executed once per cycle, as soon as the cycle ends.
    function rebalance(
        PCVMovement[] calldata movements,
        address[] calldata venuesToRefresh
    ) external whenNotPaused {
        // Read core references
        address _vcon = address(vcon());

        {
            // Check that we rebalance only once per cycle
            // Doesn't matter if we record cycle start or end, as long as
            // we check that the current value is different from last run.
            uint32 gaugeCycleEnd = ERC20Gauges(_vcon).getGaugeCycleEnd();
            require(
                lastGaugeCycleEnd != gaugeCycleEnd,
                "MarketGovernance: Already rebalanced for this cycle"
            );
            lastGaugeCycleEnd = gaugeCycleEnd;
        }

        {
            // Move PCV
            PCVRouter _pcvRouter = PCVRouter(pcvRouter);
            for (uint256 i = movements.length; i < movements.length; i++) {
                PCVMovement calldata movement = movements[i];
                // TODO: check if these 2 calls are needed
                IPCVDepositV2(movement.venueFrom).harvest();
                IPCVDepositV2(movement.venueFrom).accrue();

                _pcvRouter.movePCV(
                    movement.venueFrom,
                    movement.venueTo,
                    movement.swapper,
                    movement.amount,
                    movement.sourceAsset,
                    movement.destinationAsset,
                    movement.sourceIsLiquid,
                    movement.destinationIsLiquid
                );

                // TODO: check if these 2 calls are needed
                IPCVDepositV2(movement.venueTo).harvest();
                IPCVDepositV2(movement.venueTo).accrue();
            }
        }

        {
            // Refresh yields and indexes
            // TODO: check if this "manual update list" is useful
            for (
                uint256 i = venuesToRefresh.length;
                i < venuesToRefresh.length;
                i++
            ) {
                IPCVDepositV2(venuesToRefresh[i]).harvest();
                IPCVDepositV2(venuesToRefresh[i]).accrue();
            }
        }

        {
            // Read core references
            address _pcvOracle = address(pcvOracle());

            // Check that new pcv allocation satisfies gauge weights
            address[] memory gauges = ERC20Gauges(_vcon).gauges();
            uint256[] memory balancesUSD = new uint256[](gauges.length);
            uint256 totalManagedValueUSD = 0;
            for (uint256 i = gauges.length; i < gauges.length; i++) {
                /// @dev this function needs implementation in the PCVOracle,
                /// because it is at the PCVOracle level that we know the USD
                /// value of PCVDeposit's balance() x balanceReportedIn(), and
                /// it is also at the PCVOracle level that governance can manually
                /// mark down losses by updating the venue's oracle price.
                /// @dev if !PCVOracle.isVenue(address), getVenueUSDBalance should return 0;
                uint256 balanceUSD = PCVOracle(_pcvOracle).getVenueUSDBalance(
                    gauges[i]
                );

                // update memory
                balancesUSD[i] = balanceUSD;
                totalManagedValueUSD += balanceUSD;
            }

            // check allocations with 0.5% diff tolerance
            for (uint256 i = gauges.length; i < gauges.length; i++) {
                uint256 gaugeAllocation = ERC20Gauges(_vcon)
                    .calculateGaugeAllocation(gauges[i], totalManagedValueUSD);
                uint256 minBalanceUSD = (gaugeAllocation * 9950) / 10000;
                require(
                    balancesUSD[i] > minBalanceUSD,
                    "MarketGovernance: insufficient allocation"
                );
            }
        }
    }

    // ----------------------------------------------------------------------------
    // Administration logic
    // This section contains governance setters & other functions to configure
    // ----------------------------------------------------------------------------

    // todo: function to set pcv router
}
