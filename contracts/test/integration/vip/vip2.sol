pragma solidity =0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {ITimelockSimulation} from "../utils/ITimelockSimulation.sol";
import {ArbitrumAddresses} from "../fixtures/ArbitrumAddresses.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {PriceBoundPSM} from "../../../peg/PriceBoundPSM.sol";
import {AllRoles} from "./../utils/AllRoles.sol";
import {DSTest} from "./../../unit/utils/DSTest.sol";
import {Core} from "../../../core/Core.sol";
import {IVIP} from "./IVIP.sol";
import {Vm} from "./../../unit/utils/Vm.sol";

contract vip2 is DSTest, IVIP {
    using SafeCast for *;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    /// @notice allow 5 BIPS of deviation between new and old oracle
    uint8 public constant allowedDeviation = 5;

    /// @notice allow 100 BIPS of deviation between new and old oracle
    uint8 public constant allowedDeviationArbitrum = 100;

    /// @notice timestamp at which proposal will execute
    uint256 public constant execTime = 1659466800;

    /// --------------- Mainnet ---------------

    function getMainnetProposal()
        public
        pure
        override
        returns (ITimelockSimulation.action[] memory proposal)
    {
        proposal = new ITimelockSimulation.action[](4);

        proposal[0].target = MainnetAddresses.VOLT_USDC_PSM;
        proposal[0].value = 0;
        proposal[0].arguments = abi.encodeWithSignature(
            "setOracle(address)",
            MainnetAddresses.ORACLE_PASS_THROUGH
        );
        proposal[0].description = "Set Oracle Pass Through on USDC PSM";

        proposal[1].target = MainnetAddresses.VOLT_FEI_PSM;
        proposal[1].value = 0;
        proposal[1].arguments = abi.encodeWithSignature(
            "setOracle(address)",
            MainnetAddresses.ORACLE_PASS_THROUGH
        );
        proposal[1].description = "Set Oracle Pass Through on FEI PSM";

        proposal[2].target = MainnetAddresses.VOLT_USDC_PSM;
        proposal[2].value = 0;
        proposal[2].arguments = abi.encodeWithSignature(
            "setMintFee(uint256)",
            0
        );
        proposal[2].description = "Set mint fee to 0 on USDC PSM";

        proposal[3].target = MainnetAddresses.VOLT_FEI_PSM;
        proposal[3].value = 0;
        proposal[3].arguments = abi.encodeWithSignature(
            "setMintFee(uint256)",
            0
        );
        proposal[3].description = "Set mint fee to 0 on FEI PSM";
    }

    /// @notice mainnet usdc volt PSM
    PriceBoundPSM private immutable mainnetUsdcPSM =
        PriceBoundPSM(MainnetAddresses.VOLT_USDC_PSM);

    /// @notice mainnet fei volt PSM
    PriceBoundPSM private immutable mainnetFeiPSM =
        PriceBoundPSM(MainnetAddresses.VOLT_FEI_PSM);

    /// @notice address of the new Oracle Pass Through on mainnet
    address public oraclePassThroughMainnet =
        MainnetAddresses.ORACLE_PASS_THROUGH;

    /// @notice price of Volt on Mainnet in USDC terms prior to the upgrade
    uint256 mainnetStartingPrice;

    function mainnetSetup() public override {
        vm.warp(execTime - 1 days);
        mainnetStartingPrice = (mainnetUsdcPSM.readOracle()).value;
    }

    /// assert all contracts have their correct number of roles now,
    /// and that the proper addresses have the correct role after the governance upgrade
    function mainnetValidate() public override {
        uint256 mainnetEndingPrice = (mainnetUsdcPSM.readOracle()).value;
        /// maximum deviation of new oracle and regular oracle is 10 basis points
        assertApproxEq(
            mainnetStartingPrice.toInt256(),
            mainnetEndingPrice.toInt256(),
            allowedDeviation
        );
        assertEq(mainnetFeiPSM.mintFeeBasisPoints(), 0);
        assertEq(mainnetUsdcPSM.mintFeeBasisPoints(), 0);
        assertEq(address(mainnetFeiPSM.oracle()), oraclePassThroughMainnet);
        assertEq(address(mainnetUsdcPSM.oracle()), oraclePassThroughMainnet);
    }

    /// --------------- Arbitrum ---------------

    function getArbitrumProposal()
        public
        pure
        override
        returns (ITimelockSimulation.action[] memory proposal)
    {
        proposal = new ITimelockSimulation.action[](4);

        proposal[0].target = ArbitrumAddresses.VOLT_DAI_PSM;
        proposal[0].value = 0;
        proposal[0].arguments = abi.encodeWithSignature(
            "setOracle(address)",
            ArbitrumAddresses.ORACLE_PASS_THROUGH
        );
        proposal[0].description = "Set Oracle Pass Through on DAI PSM";

        proposal[1].target = ArbitrumAddresses.VOLT_USDC_PSM;
        proposal[1].value = 0;
        proposal[1].arguments = abi.encodeWithSignature(
            "setOracle(address)",
            ArbitrumAddresses.ORACLE_PASS_THROUGH
        );
        proposal[1].description = "Set Oracle Pass Through on USDC PSM";

        proposal[2].target = ArbitrumAddresses.VOLT_DAI_PSM;
        proposal[2].value = 0;
        proposal[2].arguments = abi.encodeWithSignature(
            "setMintFee(uint256)",
            5
        );
        proposal[2].description = "Set mint fee to 5 basis points on DAI PSM";

        proposal[3].target = ArbitrumAddresses.VOLT_USDC_PSM;
        proposal[3].value = 0;
        proposal[3].arguments = abi.encodeWithSignature(
            "setMintFee(uint256)",
            5
        );
        proposal[3].description = "Set mint fee to 5 basis points on USDC PSM";
    }

    /// @notice arbitrum usdc volt PSM
    PriceBoundPSM private immutable usdcPSM =
        PriceBoundPSM(ArbitrumAddresses.VOLT_USDC_PSM);

    /// @notice arbitrum dai volt PSM
    PriceBoundPSM private immutable daiPSM =
        PriceBoundPSM(ArbitrumAddresses.VOLT_DAI_PSM);

    /// @notice address of the new Oracle Pass Through on mainnet
    address public oraclePassThroughArbitrum =
        ArbitrumAddresses.ORACLE_PASS_THROUGH;

    /// @notice price of Volt on Arbitrum in USDC terms prior to the upgrade
    uint256 arbitrumStartingPrice;

    function arbitrumSetup() public override {
        vm.warp(execTime - 1 days);
        arbitrumStartingPrice = (usdcPSM.readOracle()).value;
    }

    function arbitrumValidate() public override {
        uint256 arbitrumEndingPrice = (usdcPSM.readOracle()).value;
        /// maximum deviation of new oracle and regular oracle is 10 basis points
        assertApproxEq(
            arbitrumStartingPrice.toInt256(),
            arbitrumEndingPrice.toInt256(),
            allowedDeviationArbitrum
        );

        assertEq(usdcPSM.mintFeeBasisPoints(), 5);
        assertEq(daiPSM.mintFeeBasisPoints(), 5);

        assertEq(address(daiPSM.oracle()), oraclePassThroughArbitrum);
        assertEq(address(usdcPSM.oracle()), oraclePassThroughArbitrum);
    }
}
