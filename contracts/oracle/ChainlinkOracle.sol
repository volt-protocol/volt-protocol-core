// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ChainlinkClient, Chainlink} from "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";

import {IScalingPriceOracle} from "./IScalingPriceOracle.sol";
import {Queue} from "./../utils/Queue.sol";

/// @notice ChainlinkOracle contract to get the latest CPI data
contract ChainlinkOracle is ChainlinkClient, Ownable, Queue {
    using Chainlink for Chainlink.Request;
    using SafeERC20 for IERC20;

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
    /// @param initialQueue queue of previous twelve months of inflation data
    constructor(
        IScalingPriceOracle _voltOracle,
        address _oracle,
        bytes32 _jobid,
        uint256 _fee,
        uint24[] memory initialQueue
    ) Ownable() Queue(initialQueue) {
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
    }

    /**
     * Create a Chainlink request to retrieve API response, find the target
     * data, then multiply by 1000 (to remove decimal places from data).
     */
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
        /// push CPI data to queue
        _unshift(uint24(_cpiData));

        /// calculate new annual CPI-U rate in basis points
        int256 aprBasisPoints = getAPRFromQueue();

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
