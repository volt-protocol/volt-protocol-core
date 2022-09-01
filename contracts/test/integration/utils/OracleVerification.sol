pragma solidity =0.8.13;

import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {ArbitrumAddresses} from "../fixtures/ArbitrumAddresses.sol";
import {IOracleRef} from "../../../refs/IOracleRef.sol";
import {Decimal} from "../../../external/Decimal.sol";

/// @notice contract to verify that all PSM's have the same
/// oracle price before and after a proposal
contract OracleVerification {
    using Decimal for Decimal.D256;

    /// @notice all PSM's on mainnet
    address[] private allMainnetPSMs = [
        MainnetAddresses.VOLT_DAI_PSM,
        MainnetAddresses.VOLT_USDC_PSM
    ];

    /// @notice all PSM's on arbitrum
    address[] private allArbitrumPSMs = [
        ArbitrumAddresses.VOLT_DAI_PSM,
        ArbitrumAddresses.VOLT_USDC_PSM
    ];

    /// @notice all oracle prices gathered during verification
    uint256[] private oraclePrices;

    /// @notice call before governance action
    function preActionVerifyOracle() internal {
        address[] storage psms = block.chainid == 1
            ? allMainnetPSMs
            : allArbitrumPSMs;
        for (uint256 i = 0; i < psms.length; i++) {
            oraclePrices.push(IOracleRef(psms[i]).readOracle().value);
        }
    }

    /// @notice call after governance action to verify oracle values
    function postActionVerifyOracle() internal view {
        address[] storage psms = block.chainid == 1
            ? allMainnetPSMs
            : allArbitrumPSMs;
        for (uint256 i = 0; i < psms.length; i++) {
            require(
                oraclePrices[i] == IOracleRef(psms[i]).readOracle().value,
                "OracleVerification: Price not the same after proposal"
            );
        }
    }
}
