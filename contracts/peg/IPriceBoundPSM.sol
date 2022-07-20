pragma solidity ^0.8.4;

interface IPriceBoundPSM {
    // ----------- Events -----------

    /// @notice event emitted when minimum floor price is updated
    event OracleFloorUpdate(uint128 oldFloor, uint128 newFloor);

    /// @notice event emitted when maximum ceiling price is updated
    event OracleCeilingUpdate(uint128 oldCeiling, uint128 newCeiling);

    // ----------- Governor or admin only state changing api -----------

    /// @notice sets the floor price in BP
    function setOracleFloorBasisPoints(uint128 newFloor) external;

    /// @notice sets the ceiling price in BP
    function setOracleCeilingBasisPoints(uint128 newCeiling) external;

    // ----------- Getters -----------

    /// @notice get the floor price in basis points
    function floor() external view returns (uint128);

    /// @notice get the ceiling price in basis points
    function ceiling() external view returns (uint128);

    /// @notice return wether the current oracle price is valid or not
    function isPriceValid() external view returns (bool);
}
