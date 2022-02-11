// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "./../utils/Timed.sol";
import "./../Constants.sol";
import "./IScalingPriceOracle.sol";
import "./ScalingPriceOracle.sol";
import "contracts/utils/Deviation.sol";
import "contracts/refs/CoreRef.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract ScalingPriceOracle is Timed, IScalingPriceOracle, CoreRef, Deviation {
    using SafeCast for *;

    /// @notice current amount that oracle price is inflating/deflating by annually in basis points
    int256 public override annualChangeRateBasisPoints;

    /// @notice oracle price. starts off at 1e18
    uint256 public oraclePrice = 1e18;

    /// @notice address that is allowed to call in and update the current price
    address public override chainlinkCPIOracle;

    /// @notice guardrails to make sure that our chainlink CPI oracle isn't borked
    uint256 public immutable maxCPIOracleChangeRateBasisPoints;

    event ChainlinkCPIOracleUpdate(address oldChainLinkCPIOracle, address newChainlinkCPIOracle);

    constructor(
        uint256 _duration,
        int256 _annualChangeRateBasisPoints,
        uint256 _maxDeviationThresholdBasisPoints,
        uint256 _maxCPIOracleChangeRateBasisPoints,
        address coreAddress,
        address _chainlinkCPIOracle
    )
        Deviation(_maxDeviationThresholdBasisPoints)
        CoreRef(coreAddress)
        Timed(_duration)
    {
        maxCPIOracleChangeRateBasisPoints = _maxCPIOracleChangeRateBasisPoints;
        annualChangeRateBasisPoints = _annualChangeRateBasisPoints;
        chainlinkCPIOracle = _chainlinkCPIOracle;

        /// start the timer
        _initTimed();
    }

    modifier onlyChainlinkCPIOracle {
        require(msg.sender == chainlinkCPIOracle, "ScalingPriceOracle: caller is not chainlink oracle");
        _;
    }

    /// @notice get the current scaled oracle price
    function getCurrentOraclePrice() public view override returns (uint256) {
        return SafeCast.toUint256(
            oraclePrice.toInt256() +
            (oraclePrice.toInt256() * annualChangeRateBasisPoints / Constants.BASIS_POINTS_GRANULARITY.toInt256() * (block.timestamp - startTime).toInt256()) / Constants.ONE_YEAR.toInt256()
        );
    }

    /// @notice internal helper method to lock in the current price.
    /// should only be used when changing the oracle price to a higher price
    function _updateOraclePrice() internal afterTimeInit {
        oraclePrice = getCurrentOraclePrice();
    }

    /// @notice function for priviledged roles to be able to upgrade the system
    function updateOracleChangeRate(int256 _newChangeRateBasisPoints) external onlyGovernorOrGuardianOrAdmin {
        require(
            isWithinDeviationThreshold(annualChangeRateBasisPoints, _newChangeRateBasisPoints),
            "ScalingPriceOracle: new change rate is outside of allowable deviation"
        );

        _updateOraclePrice();
        annualChangeRateBasisPoints = _newChangeRateBasisPoints;
    }

    /// @notice function to update the oracle price and change rate basis points in an emergency
    function emergencyUpdateOraclePrice(uint256 _oraclePrice) external onlyGuardianOrGovernor {
        oraclePrice = _oraclePrice;
        annualChangeRateBasisPoints = 0;
    }

    /// @notice function for priviledged roles to be able to upgrade the oracle system address
    function updateChainLinkCPIOracle(address _chainlinkCPIOracle) external onlyGovernorOrGuardianOrAdmin {
        address oldChainlinkCPIOracle = chainlinkCPIOracle;
        chainlinkCPIOracle = _chainlinkCPIOracle;

        emit ChainlinkCPIOracleUpdate(oldChainlinkCPIOracle, _chainlinkCPIOracle);
    }

    /// @notice function for chainlink oracle to be able to call in and change the rate
    function oracleUpdateChangeRate(int256 _newChangeRateBasisPoints) external onlyChainlinkCPIOracle afterTime {
        /// if we go into hyper inflation, then we will need to create a new contract
        require(
            maxCPIOracleChangeRateBasisPoints >= calculateDeviationThresholdBasisPoints(annualChangeRateBasisPoints, _newChangeRateBasisPoints),
            "ScalingPriceOracle: new change rate is outside of allowable CPI Oracle Deviation"
        );

        /// compound the interest with the current rate 
        _updateOraclePrice();

        /// if the oracle target is the same as last time, save an SSTORE
        if (_newChangeRateBasisPoints == annualChangeRateBasisPoints) {
            return ;
        }

        /// update the change rate basis points
        annualChangeRateBasisPoints = _newChangeRateBasisPoints;
    }

    /// @notice function to compound interest after the time period has elapsed
    function compoundInterest() external onlyGovernorOrGuardianOrAdmin {
        _updateOraclePrice();
    }

    /// @notice function to compound interest after the time period has elapsed
    function updatePeriod(uint256 newPeriod) external onlyGovernorOrAdmin {
        _setDuration(newPeriod);
    }
}
