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

/**
 * THIS IS AN EXAMPLE CONTRACT WHICH USES HARDCODED VALUES FOR CLARITY.
 * PLEASE DO NOT USE THIS CODE IN PRODUCTION.
 */
contract APIConsumer is ChainlinkClient, Ownable, Queue {
    using Chainlink for Chainlink.Request;
    using SafeERC20 for IERC20;

    uint256 public cpiData;
    int256 public immutable SCALE = 10**18;

    address public oracle; /// 0xc57B33452b4F7BB189bB5AfaE9cc4aBa1f7a4FD8
    bytes32 private jobId; /// "d5270d1c311941d0b08bead21fea7747"
    uint256 private fee;   /// 0.1 link

    IScalingPriceOracle public voltOracle;

    /// @param _oracle address of chainlink data provider
    /// @param _jobid job id
    /// @param _fee fee paid to chainlink data provider
    /// @param initialQueue queue of previous twelve months of inflation data
    constructor(
        address _oracle,
        bytes32 _jobid,
        uint256 _fee,
        uint256[] memory initialQueue
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
     * data, then multiply by 1000000000000000000 (to remove decimal places from data).
     */
    function requestCPIData() onlyOwner external returns (bytes32 requestId) {
        Chainlink.Request memory request = buildChainlinkRequest(jobId, address(this), this.fulfill.selector);

        // Set the URL to perform the GET request on
        request.add("get", "https://api.bls.gov/publicAPI/v2/timeseries/data/CUUR0000SA0?latest=true");

        request.add("path", "Results.series.data.value");

        // Multiply the result by 1000000000000000000 to remove decimals
        request.addInt("times", SCALE);

        // Sends the request
        return sendChainlinkRequestTo(oracle, request, fee);
    }

    /**
     * Receive the response in the form of uint256
     */ 
    function fulfill(bytes32 _requestId, uint256 _cpiData) external recordChainlinkFulfillment(_requestId) {
        cpiData = _cpiData;

        /// push to queue
        unshift(_cpiData);

        /// calculate new change rate in basis points
        int256 aprBasisPoints = getAPRFromQueue();

        /// send data to Volt Price Oracle
        voltOracle.oracleUpdateChangeRate(aprBasisPoints);
    }

    /// @notice withdraw link tokens, available only to owner
    function withdrawLink(address to, uint256 amount) onlyOwner external {
        IERC20(chainlinkTokenAddress()).safeTransfer(to, amount);
    }

    /// @notice withdraw arbitrary tokens from contract, available only to owner
    function withdrawToken(IERC20 token, address to, uint256 amount) onlyOwner external {
        token.safeTransfer(to, amount);
    }
    // - Implement a withdraw function to avoid locking your LINK in the contract
}
