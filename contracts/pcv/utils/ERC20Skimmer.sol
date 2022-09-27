// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPCVDeposit} from "../IPCVDeposit.sol";
import {CoreRef} from "../../refs/CoreRef.sol";

/// @notice a contract to skim all ERC20 from multiple addresses to a single destination address
/// @author Volt Protocol
contract ERC20Skimmer is CoreRef {
    /// @notice remove a pcv deposit
    event DepositRemoved(address deprecatedDeposit);

    /// @notice create a new pcv deposit
    event DepositCreated(address newDeposit);

    /// @notice skim from a PCV deposit
    event Skimmed(address indexed deposit, uint256 amount);

    /// @notice source PCV deposit to skim excess FEI from
    address public immutable target;

    /// @notice token to send
    address public immutable token;

    /// @notice address that can be pulled from
    mapping(address => bool) public isDepositWhitelisted;

    /// @notice ERC20 Skimmer
    /// @param _core VOLT Core for reference
    /// @param _target Destination for ERC20
    /// @param _token To send to the target
    constructor(
        address _core,
        address _target,
        address _token
    ) CoreRef(_core) {
        target = _target;
        token = _token;
    }

    /// @return true if source can be skimmed,
    /// condition returns true if deposit has gt 0 token balance
    /// @param deposit the deposit to pull from
    function skimEligible(address deposit) external view returns (bool) {
        return IERC20(token).balanceOf(address(deposit)) > 0;
    }

    /// @notice skim token from the source.
    /// @param deposit the deposit to skim ERC20 tokens from
    function skim(address deposit) external whenNotPaused {
        require(isDepositWhitelisted[deposit], "ERC20Skimmer: invalid target");

        uint256 amount = IERC20(token).balanceOf(address(deposit));
        IPCVDeposit(deposit).withdrawERC20(token, target, amount);

        emit Skimmed(deposit, amount);
    }

    /// @notice add a new deposit. Only Governor can call
    /// @param newDeposit the new deposit to skim from
    function addDeposit(address newDeposit) external onlyGovernor {
        require(
            !isDepositWhitelisted[newDeposit],
            "ERC20Skimmer: already in list"
        );

        isDepositWhitelisted[newDeposit] = true;

        emit DepositCreated(newDeposit);
    }

    /// @notice remove a deposit. Only Governor can call
    /// @param deprecatedDeposit the deposit that cannot be skimmed from
    function removeDeposit(address deprecatedDeposit) external onlyGovernor {
        require(
            isDepositWhitelisted[deprecatedDeposit],
            "ERC20Skimmer: not in list"
        );

        isDepositWhitelisted[deprecatedDeposit] = false;

        emit DepositRemoved(deprecatedDeposit);
    }
}
