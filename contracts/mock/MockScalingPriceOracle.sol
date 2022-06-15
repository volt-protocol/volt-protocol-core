// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {CoreRef} from "./../refs/CoreRef.sol";
import {ScalingPriceOracle, ChainlinkClient, Chainlink} from "./../oracle/ScalingPriceOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Testing contract that allows for updates without mocking chainlink calls
contract MockScalingPriceOracle is ScalingPriceOracle {
    using Chainlink for Chainlink.Request;

    address owner;

    constructor(
        address _oracle,
        bytes32 _jobid,
        uint256 _fee,
        uint128 _currentMonth,
        uint128 _previousMonth,
        address _chainlinkToken
    )
        ScalingPriceOracle(
            _oracle,
            _jobid,
            _fee,
            _currentMonth,
            _previousMonth,
            _chainlinkToken
        )
    {
        owner = msg.sender;
    }

    function fulfill(uint256 _cpiData) external {
        _updateCPIData(_cpiData);
    }

    function compoundInterest() public {
        _oracleUpdateChangeRate(monthlyChangeRateBasisPoints);
    }

    function setStartTime(uint256 newStartTime) public {
        startTime = newStartTime;
    }

    function setStartTimeAndCompoundInterest(uint256 newStartTime) public {
        setStartTime(newStartTime);
        compoundInterest();
    }

    function rescueTokens(
        IERC20 token,
        address to,
        uint256 amount
    ) external {
        require(msg.sender == owner, "!owner");

        token.transfer(to, amount);
    }
}
