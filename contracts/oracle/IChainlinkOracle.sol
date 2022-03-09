// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {IScalingPriceOracle} from "./IScalingPriceOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice ChainlinkOracle contract to get the latest CPI data
interface IChainlinkOracle {
    /// @notice address of chainlink oracle to send request
    function oracle() external view returns (address);

    /// @notice job id that retrieves the latest CPI data
    function jobId() external view returns (bytes32);

    /// @notice amount in LINK paid to node operator for each request
    function fee() external view returns (bytes32);

    /// @notice address of the volt scaling price oracle
    function voltOracle() external view returns (IScalingPriceOracle);

    /// @notice function to request data
    function requestCPIData() external returns (bytes32 requestId);

    /// @notice Receive the response in the form of uint256
    /// @param _requestId of the chainlink request
    /// @param _cpiData latest CPI data
    function fulfill(bytes32 _requestId, uint256 _cpiData) external;

    /// @notice withdraw link tokens, available only to owner
    /// @param to recipient
    /// @param amount sent to recipient
    function withdrawLink(address to, uint256 amount) external;

    /// @notice withdraw arbitrary tokens from contract, available only to owner
    /// @param token asset to withdraw
    /// @param to recipient
    /// @param amount sent to recipient
    function withdrawToken(
        IERC20 token,
        address to,
        uint256 amount
    ) external;

    /// @notice function to set new LINK fee
    /// @param newFee sent to node operator
    function setFee(uint256 newFee) external;

    /// @notice function to set the job id
    /// @param _jobId sent to node operator
    function setJobID(bytes32 _jobId) external;

    /// @notice function to set the scaling price oracle address
    /// @param newScalingPriceOracle address
    function setScalingPriceOracle(IScalingPriceOracle newScalingPriceOracle)
        external;

    /// @notice function to set the chainlink oracle address that requests are made to
    /// @param newChainlinkOracle new chainlink oracle
    function setChainlinkOracleAddress(address newChainlinkOracle) external;
}
