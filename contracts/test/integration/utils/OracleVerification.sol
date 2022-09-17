pragma solidity =0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {Decimal} from "../../../external/Decimal.sol";
import {Deviation} from "../../../utils/Deviation.sol";
import {IOracleRef} from "../../../refs/IOracleRef.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {ArbitrumAddresses} from "../fixtures/ArbitrumAddresses.sol";

/// @notice contract to verify that all PSM's have the same
/// oracle price before and after a proposal
contract OracleVerification {
    using Decimal for Decimal.D256;
    using SafeCast for *;
    using Deviation for *;

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

    /// @notice address all psm oracles should point to
    address private cachedOracle;

    /// @notice call before governance action
    function preActionVerifyOracle() internal {
        address[] storage psms = block.chainid == 1
            ? allMainnetPSMs
            : allArbitrumPSMs;

        for (uint256 i = 0; i < psms.length; i++) {
            if (cachedOracle == address(0)) {
                cachedOracle = address(IOracleRef(psms[i]).oracle());
            } else {
                require(
                    cachedOracle == address(IOracleRef(psms[i]).oracle()),
                    "OracleVerification: Invalid oracle"
                );
            }
            oraclePrices.push(IOracleRef(psms[i]).readOracle().value);
        }
    }

    /// @notice call after governance action to verify oracle values
    function postActionVerifyOracle() internal view {
        address[] storage psms = block.chainid == 1
            ? allMainnetPSMs
            : allArbitrumPSMs;

        for (uint256 i = 0; i < psms.length; i++) {
            uint256 deviationBasisPoints = Deviation
                .calculateDeviationThresholdBasisPoints(
                    IOracleRef(psms[i]).readOracle().value.toInt256(),
                    oraclePrices[i].toInt256()
                );
            require(
                deviationBasisPoints == 0,
                "OracleVerification: Price not the same after proposal"
            );
            require(
                cachedOracle == address(IOracleRef(psms[i]).oracle()),
                "OracleVerification: oracle not the same after proposal"
            );
        }
    }
}
