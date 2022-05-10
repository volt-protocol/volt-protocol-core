// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICore, IFeiSavingsRate} from "./IFeiSavingsRate.sol";
import {Constants} from "./../Constants.sol";

/// @notice contract that streams payment to Volt Protocol based
/// on the amount of Fei the VCON DAO holds
/// Any governor in the Fei System can claw back the unvested Fei.
/// The earn function is public and callable by any ethereum account
/// as long as there is interest that has not been accrued
/// Interest is based on a simple interest or APR formula
/// this means that interest does not compound over time.
contract FeiSavingsRate is IFeiSavingsRate {
    using SafeERC20 for IERC20;

    /// @notice the recipient of the fei savings rate
    address public immutable override recipient;

    /// @notice the address of the contract that will hold Fei that is paid interest
    address public immutable override feiHolder;

    /// @notice reference to the Fei ERC20 token implementation
    IERC20 public immutable override fei;

    /// @notice any governor in the Fei System can claw back the unvested Fei.
    ICore public immutable override feiCore;

    /// @notice FEI Protocol will pay 300 basis points or 3% on all held FEI
    uint256 public constant override basisPointsPayout = 300;

    /// @notice the last block timestamp where payouts occurred
    uint40 public override lastRecordedPayout;

    /// @notice the last amount of Fei the Volt Protocol smart contract held
    uint216 public override lastFeiAmount;

    /// @notice instantiate the Fei Savings Rate for the Volt Protocol
    constructor(
        address _recipient,
        address _feiHolder,
        IERC20 _fei,
        ICore _feiCore
    ) {
        recipient = _recipient;
        feiHolder = _feiHolder;
        fei = _fei;
        feiCore = _feiCore;

        /// init the contract with the starting state
        lastRecordedPayout = uint40(block.timestamp);
        lastFeiAmount = uint216(_fei.balanceOf(_feiHolder));
    }

    // ----------- Getter -----------

    /// @notice view only function that returns the amount of unpaid interest
    function getPendingInterest()
        public
        view
        returns (uint256 interestAccrued)
    {
        uint256 timeDelta = block.timestamp - lastRecordedPayout;
        interestAccrued =
            (timeDelta * lastFeiAmount * basisPointsPayout) /
            Constants.BASIS_POINTS_GRANULARITY /
            Constants.ONE_YEAR;
    }

    // ----------- State changing API -----------

    /// @notice function that accrues and then pays out interest based on the amount of Fei Held
    /// records the new amount of Fei held
    function earnInterest() external override {
        /// Checks
        require(
            block.timestamp > lastRecordedPayout,
            "Fei Savings Rate: No interest to pay"
        );

        uint256 interestAccrued = getPendingInterest();

        /// this should never lose accuracy as unix time maxes out at uint32.max and then resets
        uint40 newBlockTimestamp = uint40(block.timestamp);

        /// this should always be accurate and not lose precision in this downcast as uint216
        /// is 184857846336289696793279630697325587536 times larger than the current Fei supply
        uint216 newFeiAmount = uint216(fei.balanceOf(feiHolder));

        /// Effects
        lastRecordedPayout = newBlockTimestamp;
        lastFeiAmount = newFeiAmount;

        /// Interactions
        fei.safeTransfer(recipient, interestAccrued);

        emit InterestPaid(interestAccrued);
    }

    /// @notice function that only the Tribe DAO governor can call to cancel the FSR for Volt
    /// this removes all Fei from the FSR contract and sends that Fei to the caller
    function clawback() external override {
        /// Check
        require(
            feiCore.isGovernor(msg.sender),
            "Fei Savings Rate: Not Fei governor"
        );

        uint40 newBlockTimestamp = uint40(block.timestamp);

        /// Effects
        lastRecordedPayout = newBlockTimestamp; /// jump to latest block
        lastFeiAmount = 0; /// zero fei balance
        /// this zero's out the existing unpaid rewards stream

        uint256 feiBalance = fei.balanceOf(address(this));
        /// Interactions
        fei.safeTransfer(msg.sender, feiBalance);

        emit Clawback(feiBalance);
    }
}
