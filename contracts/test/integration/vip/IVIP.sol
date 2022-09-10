pragma solidity =0.8.13;

import {ITimelockSimulation} from "../utils/ITimelockSimulation.sol";

/// @notice standard interface all VIPs must comply with
interface IVIP {
    /// @notice function to do any pre-test actions
    function mainnetSetup() external;

    function arbitrumSetup() external;

    /// @notice validate all changes post execution
    function mainnetValidate() external;

    function arbitrumValidate() external;

    /// @notice get the proposal calldata
    function getMainnetProposal()
        external
        returns (ITimelockSimulation.action[] memory proposal);

    function getArbitrumProposal()
        external
        pure
        returns (ITimelockSimulation.action[] memory proposal);
}
