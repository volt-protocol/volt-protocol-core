pragma solidity =0.8.13;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {ArbitrumAddresses} from "../fixtures/ArbitrumAddresses.sol";
import {IOracleRef} from "../../../refs/IOracleRef.sol";
import {Deviation} from "../../../utils/Deviation.sol";
import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";
import {IPCVDeposit} from "../../../pcv/IPCVDeposit.sol";
import {Vm} from "./../../unit/utils/Vm.sol";
import {DSTest} from "./../../unit/utils/DSTest.sol";

import "hardhat/console.sol";

/// @notice contract to verify that all PSM's have the same
/// oracle price before and after a proposal
contract PCVGuardVerification is DSTest {
    using Deviation for *;
    using SafeCast for *;

    /// TODO add arbitrum support

    /// @notice all PSM's on mainnet
    address[] private allMainnetPCVDeposits = [
        MainnetAddresses.VOLT_DAI_PSM,
        MainnetAddresses.VOLT_FEI_PSM,
        MainnetAddresses.VOLT_USDC_PSM,
        MainnetAddresses.COMPOUND_DAI_PCV_DEPOSIT,
        MainnetAddresses.COMPOUND_FEI_PCV_DEPOSIT,
        MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT
    ];

    /// @notice all PSM's on arbitrum
    address[] private allArbitrumPCVDeposits = [
        ArbitrumAddresses.VOLT_DAI_PSM,
        ArbitrumAddresses.VOLT_USDC_PSM
    ];

    /// @notice all places pcv could be, but aren't pcv deposits on mainnet
    address[] private allMainnetDeposits = [
        MainnetAddresses.GOVERNOR,
        MainnetAddresses.TIMELOCK_CONTROLLER
    ];

    /// @notice all places pcv could be, but aren't pcv deposits on mainnet
    address[] private allArbitrumDeposits = [
        ArbitrumAddresses.GOVERNOR,
        ArbitrumAddresses.TIMELOCK_CONTROLLER
    ];

    /// @notice all tokens currently in VOLT Protocol's PCV on mainnet
    IERC20[] private allMainnetTokens = [
        IERC20(MainnetAddresses.USDC),
        IERC20(MainnetAddresses.FEI),
        IERC20(MainnetAddresses.DAI),
        IERC20(MainnetAddresses.VOLT)
    ];

    /// @notice all tokens currently in VOLT Protocol's PCV on arbitrum
    IERC20[] private allArbitrumTokens = [
        IERC20(ArbitrumAddresses.USDC),
        IERC20(ArbitrumAddresses.DAI),
        IERC20(ArbitrumAddresses.VOLT)
    ];

    /// @notice balance of each token before timelock action
    mapping(address => uint256) private balancePerTokenPre;

    /// @notice balance of each token after timelock action
    mapping(address => uint256) private balancePerTokenPost;

    uint256 private totalPCVPre;

    uint256 private totalPCVPost;

    /// @notice call before governance action
    function preActionVerifyPCV() internal {
        address[] storage allDeposits = block.chainid == 1
            ? allMainnetPCVDeposits
            : allArbitrumPCVDeposits;

        /// get balance of all pcv deposits
        for (uint256 i = 0; i < allDeposits.length; i++) {
            IPCVDeposit deposit = IPCVDeposit(allDeposits[i]);
            balancePerTokenPre[deposit.balanceReportedIn()] += deposit
                .balance();

            if (
                deposit.balanceReportedIn() == MainnetAddresses.USDC ||
                deposit.balanceReportedIn() == ArbitrumAddresses.USDC
            ) {
                totalPCVPre += deposit.balance() * 1e12;
            } else {
                totalPCVPre += deposit.balance();
            }
        }

        IERC20[] storage allTokens = block.chainid == 1
            ? allMainnetTokens
            : allArbitrumTokens;

        address[] storage allNonPCVDeposits = block.chainid == 1
            ? allMainnetDeposits
            : allArbitrumDeposits;

        /// get balance of all non pcv deposits
        for (uint256 i = 0; i < allTokens.length; i++) {
            for (uint256 j = 0; j < allNonPCVDeposits.length; j++) {
                if (
                    address(allTokens[i]) == MainnetAddresses.USDC ||
                    address(allTokens[i]) == ArbitrumAddresses.USDC
                ) {
                    totalPCVPre +=
                        allTokens[i].balanceOf(allNonPCVDeposits[j]) *
                        1e12;
                } else {
                    totalPCVPre += allTokens[i].balanceOf(allNonPCVDeposits[j]);
                }
            }
        }
    }

    /// @notice call after governance action to verify oracle values
    function postActionVerifyPCV(Vm vm) internal {
        address[] storage allDeposits = block.chainid == 1
            ? allMainnetPCVDeposits
            : allArbitrumPCVDeposits;

        /// get balance of all pcv deposits
        for (uint256 i = 0; i < allDeposits.length; i++) {
            IPCVDeposit deposit = IPCVDeposit(allDeposits[i]);
            balancePerTokenPost[deposit.balanceReportedIn()] += deposit
                .balance();

            if (
                deposit.balanceReportedIn() == MainnetAddresses.USDC ||
                deposit.balanceReportedIn() == ArbitrumAddresses.USDC
            ) {
                totalPCVPre += deposit.balance() * 1e12;
            } else {
                totalPCVPre += deposit.balance();
            }
        }

        IERC20[] storage allTokens = block.chainid == 1
            ? allMainnetTokens
            : allArbitrumTokens;

        address[] storage allNonPCVDeposits = block.chainid == 1
            ? allMainnetDeposits
            : allArbitrumDeposits;

        /// get balance of all non pcv deposits
        for (uint256 i = 0; i < allTokens.length; i++) {
            for (uint256 j = 0; j < allNonPCVDeposits.length; j++) {
                if (
                    address(allTokens[i]) == MainnetAddresses.USDC ||
                    address(allTokens[i]) == ArbitrumAddresses.USDC
                ) {
                    totalPCVPost +=
                        allTokens[i].balanceOf(allNonPCVDeposits[j]) *
                        1e12;
                } else {
                    totalPCVPost += allTokens[i].balanceOf(
                        allNonPCVDeposits[j]
                    );
                }
            }
        }

        console.log("\n ~~~ PCV Stats ~~~");
        console.log("pcv pre proposal: ", totalPCVPre);
        console.log("pcv post proposal: ", totalPCVPost);
        console.log(
            "actual slippage: ",
            Deviation.calculateDeviationThresholdBasisPoints(
                totalPCVPost.toInt256(),
                totalPCVPre.toInt256()
            )
        );
        console.log("");

        /// allow 3 bips slippage per proposal
        require(
            Deviation.isWithinDeviationThreshold(
                3,
                totalPCVPost.toInt256(),
                totalPCVPre.toInt256()
            ),
            "PCVGuardVerification: pcv slippage error"
        );

        /// use pcv guard to withdraw and then revert to roll back all state changes
        vm.expectRevert("success");
        this.simulateAllWithdrawals(vm);
    }

    function simulateAllWithdrawals(Vm vm) external {
        for (uint256 i = 0; i < allMainnetPCVDeposits.length; i++) {
            vm.prank(MainnetAddresses.EOA_1);
            PCVGuardian(MainnetAddresses.PCV_GUARDIAN).withdrawAllToSafeAddress(
                    allMainnetPCVDeposits[i]
                );
        }

        revert("success"); /// always revert so as not to mess up mint and redeem tests
    }
}
