// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Decimal} from "../external/Decimal.sol";
import {CoreRef} from "./../refs/CoreRef.sol";
import {ScalingPriceOracle} from "./ScalingPriceOracle.sol";
import {IOraclePassThrough} from "./IOraclePassThrough.sol";

/// @notice contract that passes all price calls to the Scaling Price Oracle
/// The Scaling Price Oracle can be changed if there is a decision to change how data is interpolated
/// without needing all contracts in the system to be upgraded, only this contract will have to change where it points
/// @author Elliot Friedman
contract OraclePassThrough is IOraclePassThrough {
    using Decimal for Decimal.D256;

    /// ---------- Immutable Variables ----------

    /// @notice address of the VOLT governor
    address public immutable voltGovernor;

    /// @notice address of the FRAX governor
    address public immutable fraxGovernor;

    /// ---------- Mutable Variables ----------

    /// @notice reference to the scaling price oracle
    ScalingPriceOracle public override scalingPriceOracle;

    /// @notice sign offs on the new scaling price oracle changes by address
    mapping(address => mapping(ScalingPriceOracle => bool)) public signOffs;

    /// @notice event emitted when the scaling price oracle is updated
    event ScalingPriceOracleUpdate(
        ScalingPriceOracle oldScalingPriceOracle,
        ScalingPriceOracle newScalingPriceOracle
    );

    constructor(
        ScalingPriceOracle _scalingPriceOracle,
        address _voltGovernor,
        address _fraxGovernor
    ) {
        scalingPriceOracle = _scalingPriceOracle;
        voltGovernor = _voltGovernor;
        fraxGovernor = _fraxGovernor;
    }

    // ----------- Governance Modifier -----------

    modifier onlyVoltOrFrax() {
        require(
            msg.sender == voltGovernor || msg.sender == fraxGovernor,
            "ScalingPriceOracle: not VOLT or FRAX"
        );
        _;
    }

    /// @notice updates the oracle price
    /// @dev no-op, ScalingPriceOracle is updated automatically
    /// added for backwards compatibility with OracleRef
    function update() public {}

    // ----------- Getters -----------

    /// @notice function to get the current oracle price for the OracleRef contract
    function read()
        external
        view
        override
        returns (Decimal.D256 memory price, bool valid)
    {
        uint256 currentPrice = scalingPriceOracle.getCurrentOraclePrice();

        price = Decimal.from(currentPrice).div(1 ether);
        valid = true;
    }

    /// @notice function to get the current oracle price for the entire system
    function getCurrentOraclePrice() external view override returns (uint256) {
        return scalingPriceOracle.getCurrentOraclePrice();
    }

    // ----------- Governance only state changing api -----------

    /// @notice function to update the pointer to the scaling price oracle
    /// requires approval from both VOLT and FRAX governance to sign off on the change
    function updateScalingPriceOracle(ScalingPriceOracle newScalingPriceOracle)
        external
        override
        onlyVoltOrFrax
    {
        require(
            !signOffs[msg.sender][newScalingPriceOracle],
            "ScalingPriceOracle: change already signed off"
        );

        address oppositeGovernor = msg.sender == voltGovernor
            ? fraxGovernor
            : voltGovernor;

        /// if other governor has signed off on this change, save an SSTORE
        if (signOffs[oppositeGovernor][newScalingPriceOracle]) {
            delete signOffs[oppositeGovernor][newScalingPriceOracle];

            ScalingPriceOracle oldScalingPriceOracle = scalingPriceOracle;
            scalingPriceOracle = newScalingPriceOracle;

            emit ScalingPriceOracleUpdate(
                oldScalingPriceOracle,
                newScalingPriceOracle
            );
        } else {
            /// if other governor has not signed off on this change, write to storage
            signOffs[msg.sender][newScalingPriceOracle] = true;
        }
    }
}
