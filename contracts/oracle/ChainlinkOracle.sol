// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";

import "./IScalingPriceOracle.sol";
import "./../utils/Queue.sol";

/**
 * Request testnet LINK and ETH here: https://faucets.chain.link/
 * Find information on LINK Token Contracts and get the latest ETH and LINK faucets here: https://docs.chain.link/docs/link-token-contracts/
 */

/// @notice ChainlinkOracle contract to get the latest CPI data
contract ChainlinkOracle is ChainlinkClient, Ownable, Queue {
    using Chainlink for Chainlink.Request;
    using SafeERC20 for IERC20;

    /// @notice both of these variables are immutable to save gas
    address public immutable oracle; /// 0xc57B33452b4F7BB189bB5AfaE9cc4aBa1f7a4FD8
    bytes32 public immutable jobId; /// "d5270d1c311941d0b08bead21fea7747"

    /// @notice amount in LINK paid to node operator for each request
    uint256 public fee;

    /// @notice address of the volt scaling price oracle
    IScalingPriceOracle public voltOracle;

    /// @param _oracle address of chainlink data provider
    /// @param _jobid job id
    /// @param _fee fee paid to chainlink data provider
    /// @param initialQueue queue of previous twelve months of inflation data
    constructor(
        address _oracle,
        bytes32 _jobid,
        uint256 _fee,
        uint24[] memory initialQueue
    )
        Ownable()
        Queue(initialQueue)
    {
        setPublicChainlinkToken();
        oracle = _oracle;
        jobId = _jobid;
        fee = _fee;
    }

    /**
     * Create a Chainlink request to retrieve API response, find the target
     * data, then multiply by 1000 (to remove decimal places from data).
     */
    function requestCPIData() external onlyOwner returns (bytes32 requestId) {
        Chainlink.Request memory request = buildChainlinkRequest(jobId, address(this), this.fulfill.selector);

        return sendChainlinkRequestTo(oracle, request, fee);
    }

    /**
     * Receive the response in the form of uint256
     */
    /// TODO figure out if we need to enforce that there is a correct request ID here
    /// it should, but still double check with chainlink
    /// @param _requestId of the chainlink request
    /// @param _cpiData latest CPI data
    function fulfill(bytes32 _requestId, uint256 _cpiData) external recordChainlinkFulfillment(_requestId) {
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
    function withdrawToken(IERC20 token, address to, uint256 amount) external onlyOwner {
        token.safeTransfer(to, amount);
    }

    /// @notice function to set new LINK fee
    /// @param newFee sent to node operator
    function setFee(uint256 newFee) external onlyOwner {
        fee = newFee;
    }
}
