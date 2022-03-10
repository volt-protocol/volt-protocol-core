// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ChainlinkClient, Chainlink} from "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";

import {IScalingPriceOracle} from "./IScalingPriceOracle.sol";
import {Constants} from "./../Constants.sol";

/// @notice ChainlinkOracle contract to get the latest CPI data and then send it in to
/// the ScalingPriceOracle
contract ChainlinkOracle is ChainlinkClient, Ownable, Initializable {
    using Chainlink for Chainlink.Request;
    using SafeERC20 for IERC20;
    using SafeCast for *;

    /// @notice the current month's CPI data
    uint128 public currentMonth;

    /// @notice the previous month's CPI data
    uint128 public previousMonth;

    /// @notice address of chainlink oracle to send request
    address public oracle;

    /// @notice job id that retrieves the latest CPI data
    bytes32 public jobId;

    /// @notice amount in LINK paid to node operator for each request
    uint256 public fee;

    /// @notice address of the volt scaling price oracle
    IScalingPriceOracle public voltOracle;

    /// @param _voltOracle address of the scaling price oracle
    /// @param _oracle address of chainlink data provider
    /// @param _jobid job id
    /// @param _fee fee paid to chainlink data provider
    /// @param _currentMonth current month's inflation data
    /// @param _previousMonth previous month's inflation data
    constructor(
        IScalingPriceOracle _voltOracle,
        address _oracle,
        bytes32 _jobid,
        uint256 _fee,
        uint128 _currentMonth,
        uint128 _previousMonth
    ) Ownable() {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        if (chainId == 1 || chainId == 42) {
            setPublicChainlinkToken();
        }

        oracle = _oracle;
        jobId = _jobid;
        fee = _fee;

        voltOracle = _voltOracle;

        currentMonth = _currentMonth;
        previousMonth = _previousMonth;
    }

    /// ------------- Getters -------------

    /// @notice get APR from chainlink data by measuring (current month - previous month) / previous month
    /// @return percentageChange percentage change in basis points over past month
    function getMonthlyAPR() public view returns (int256 percentageChange) {
        int256 delta = int128(currentMonth) - int128(previousMonth);
        percentageChange =
            (delta * Constants.BASIS_POINTS_GRANULARITY_INT) /
            int128(previousMonth);
    }

    /// ------------- Helpers -------------

    /// @notice this is the only method needed as we will be storing the most recent 2 months of data
    /// @param newMonth the new month to store
    function _addNewMonth(uint128 newMonth) internal {
        previousMonth = currentMonth;

        currentMonth = newMonth;
    }

    /// ------------- Admin and Chainlink Operator API -------------

    /// @notice Create a Chainlink request to retrieve API response, find the target
    /// data, then multiply by 1000 (to remove decimal places from data).
    /// @return requestId for this request
    function requestCPIData() external onlyOwner returns (bytes32 requestId) {
        Chainlink.Request memory request = buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfill.selector
        );

        return sendChainlinkRequestTo(oracle, request, fee);
    }

    /// @notice Receive the response in the form of uint256
    /// @param _requestId of the chainlink request
    /// @param _cpiData latest CPI data
    function fulfill(bytes32 _requestId, uint256 _cpiData)
        external
        recordChainlinkFulfillment(_requestId)
    {
        /// store CPI data, removes stale data
        _addNewMonth(uint128(_cpiData));

        /// calculate new monthly CPI-U rate in basis points
        int256 aprBasisPoints = getMonthlyAPR();

        /// send data to Volt Price Oracle
        voltOracle.oracleUpdateChangeRate(aprBasisPoints);
    }

    /// @notice withdraw link tokens, available only to owner
    /// @param to recipient
    /// @param amount sent to recipient
    function withdrawLink(address to, uint256 amount) external onlyOwner {
        IERC20(chainlinkTokenAddress()).safeTransfer(to, amount);
    }

    /// @notice withdraw arbitrary tokens from contract, available only to owner
    /// @param token asset to withdraw
    /// @param to recipient
    /// @param amount sent to recipient
    function withdrawToken(
        IERC20 token,
        address to,
        uint256 amount
    ) external onlyOwner {
        token.safeTransfer(to, amount);
    }

    /// @notice function to set new LINK fee
    /// @param newFee sent to node operator
    function setFee(uint256 newFee) external onlyOwner {
        fee = newFee;
    }

    /// @notice function to set the job id
    /// @param _jobId sent to node operator
    function setJobID(bytes32 _jobId) external onlyOwner {
        jobId = _jobId;
    }

    /// @notice function to set the scaling price oracle address
    /// @param newScalingPriceOracle address
    function setScalingPriceOracle(IScalingPriceOracle newScalingPriceOracle)
        external
        onlyOwner
    {
        voltOracle = newScalingPriceOracle;
    }

    /// @notice function to set the chainlink oracle address that requests are made to
    /// @param newChainlinkOracle new chainlink oracle
    function setChainlinkOracleAddress(address newChainlinkOracle)
        external
        onlyOwner
    {
        oracle = newChainlinkOracle;
    }
}
