pragma solidity 0.8.13;

interface IPCVOracle {
    // ----------- Events ------------------------------------------

    /// @notice emitted when a new venue oracle is set
    event VenueOracleUpdated(
        address indexed venue,
        address indexed oldOracle,
        address indexed newOracle
    );

    /// @notice emitted when a new venue is added
    event VenueAdded(address indexed venue, uint256 timestamp);

    /// @notice emitted when a venue is removed
    event VenueRemoved(address indexed venue, uint256 timestamp);

    /// @notice emitted when total venue PCV changes
    event PCVUpdated(
        address indexed venue,
        uint256 timestamp,
        int256 deltaBalance,
        int256 deltaProfit
    );

    /// @notice track the venue's profit and losses
    struct VenueData {
        /// @notice the decimal normalized last recorded balance of PCV Deposit
        /// lastRecordedPCV can never go negative, if it does,
        /// governance markdown and removal flow will occur
        uint128 lastRecordedPCV;
        /// @notice the decimal normalized last recorded profit of PCV Deposit
        int128 lastRecordedProfit;
    }

    // ----------- Getters -----------------------------------------

    /// @notice venue information, balance and profit
    function venueRecord(address venue) external view returns (uint128, int128);

    /// @notice Map from venue address to oracle address. By reading an oracle
    /// value and multiplying by the PCVDeposit's balance(), the PCVOracle can
    /// know the USD value of PCV deployed in a given venue.
    function venueToOracle(address venue) external returns (address oracle);

    /// @notice return all addresses listed as liquid venues
    function getVenues() external view returns (address[] memory);

    /// @notice get total number of venues
    function getNumVenues() external view returns (uint256);

    /// @notice check if a venue is in the list of venues
    /// @param venue address to check
    /// @return boolean whether or not the venue is part of the venue list
    function isVenue(address venue) external view returns (bool);

    /// @notice return the non-decimal normalized last recorded balance for venue
    function lastRecordedPCVRaw(address venue) external view returns (uint256);

    /// @notice return the decimal normalized last recorded balance for venue
    function lastRecordedPCV(address venue) external view returns (uint256);

    /// @notice return the decimal normalized last recorded profit for venue
    function lastRecordedProfit(address venue) external view returns (int128);

    /// @notice get the total PCV balance by looping through the pcv deposits
    /// @dev this function is meant to be used offchain, as it is pretty gas expensive.
    /// this is an unsafe operation as it does not enforce the system is in an unlocked state
    function getTotalPcv() external view returns (uint256 totalPcv);

    /// @notice returns decimal normalized version of a given venues USD balance
    function getVenueBalance(address venue) external view returns (uint256);

    // ----------- PCVDeposit-only State changing API --------------

    /// @notice hook on PCV deposit, callable when pcv oracle is set
    /// updates the oracle with the new balance delta and profits
    function updateBalance(int256 deltaBalance, int256 deltaProfit) external;

    // ----------- Governor-only State changing API ----------------

    /// @notice set the oracle for a given venue, used to normalize
    /// balances into USD values, and correct for exceptional gains
    /// and losses that are not properly reported by the PCVDeposit
    function setVenueOracle(address venue, address newOracle) external;

    /// @notice add venues to the oracle
    /// only callable by the governor
    /// This locks system at level 1, because it needs to accrue
    /// on the added PCV Deposits (that locks at level 2).
    function addVenues(
        address[] calldata venues,
        address[] calldata oracles
    ) external;

    /// @notice remove venues from the oracle
    /// only callable by the governor
    /// This locks system at level 1, because it needs to accrue
    /// on the added PCV Deposits (that locks at level 2).
    function removeVenues(address[] calldata venues) external;
}
