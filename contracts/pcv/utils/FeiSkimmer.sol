// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "../IPCVDeposit.sol"; 
import "../../refs/CoreRef.sol";

/// @title a contract to skim excess Volt from addresses
/// @author FEI Protocol
contract FeiSkimmer is CoreRef {
 
    event ThresholdUpdate(uint256 newThreshold);

    /// @notice source PCV deposit to skim excess Volt from
    IPCVDeposit public immutable source;

    /// @notice the threshold of Volt above which to skim
    uint256 public threshold;

    /// @notice Volt Skimmer
    /// @param _core Volt Core for reference
    /// @param _source the target to skim from
    /// @param _threshold the threshold of Volt to be maintained by source
    constructor(
        address _core,
        IPCVDeposit _source,
        uint256 _threshold
    ) 
        CoreRef(_core)
    {
        source = _source;
        threshold = _threshold;
        emit ThresholdUpdate(threshold);
    }

    /// @return true if Volt balance of source exceeds threshold
    function skimEligible() external view returns (bool) {
        return volt.balanceOf(address(source)) > threshold;
    }

    /// @notice skim Volt above the threshold from the source. Pausable. Requires skimEligible()
    function skim()
        external
        whenNotPaused
    {
        IVolt _volt = volt; /// save gas by pushing this value onto the stack instead of reading from storage

        uint256 voltTotal = _volt.balanceOf(address(source));

        require(voltTotal > threshold, "under threshold");
        
        uint256 burnAmount = voltTotal - threshold;
        source.withdrawERC20(address(_volt), address(this), burnAmount);

        _volt.burn(burnAmount);
    }
    
    /// @notice set the threshold for volt skims. Only Governor or Admin
    /// @param newThreshold the new value above which volt is skimmed.
    function setThreshold(uint256 newThreshold) external onlyGovernorOrAdmin {
        threshold = newThreshold;
        emit ThresholdUpdate(newThreshold);
    }
}