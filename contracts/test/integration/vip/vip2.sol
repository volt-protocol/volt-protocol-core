pragma solidity =0.8.13;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {TimelockSimulation} from "../utils/TimelockSimulation.sol";
import {ArbitrumAddresses} from "../fixtures/ArbitrumAddresses.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {PriceBoundPSM} from "../../../peg/PriceBoundPSM.sol";
import {AllRoles} from "./../utils/AllRoles.sol";
import {DSTest} from "./../../unit/utils/DSTest.sol";
import {Core} from "../../../core/Core.sol";
import {IVIP} from "./IVIP.sol";
import {Vm} from "./../../unit/utils/Vm.sol";

contract vip2 is DSTest, IVIP, AllRoles {
    using SafeCast for *;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    /// --------------- Mainnet ---------------

    function getMainnetProposal()
        public
        pure
        override
        returns (TimelockSimulation.action[] memory proposal)
    {
        proposal = new TimelockSimulation.action[](4);

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
    PriceBoundPSM private immutable mainnetusdcPSM =
        PriceBoundPSM(MainnetAddresses.VOLT_USDC_PSM);

    /// @notice price of Volt on Arbitrum in USDC terms prior to the upgrade
    uint256 mainnetStartingPrice;

    function mainnetSetup() public override {
        vm.prank(MainnetAddresses.GOVERNOR);
        Core(MainnetAddresses.CORE).grantGovernor(
            MainnetAddresses.TIMELOCK_CONTROLLER
        );

        mainnetStartingPrice = (usdcPSM.readOracle()).value;
    }

    /// assert all contracts have their correct number of roles now,
    /// and that the proper addresses have the correct role after the governance upgrade
    function mainnetValidate() public override {
        _setupMainnet(Core(MainnetAddresses.CORE));
        testRoleArity();

        _setupMainnet(Core(MainnetAddresses.CORE));
        testRoleAddresses(Core(MainnetAddresses.CORE));

        uint256 arbitrumEndingPrice = (usdcPSM.readOracle()).value;
        /// maximum deviation of new oracle and regular oracle is 10 basis points
        assertApproxEq(
            arbitrumStartingPrice.toInt256(),
            arbitrumEndingPrice.toInt256(),
            10
        );
    }

    /// --------------- Arbitrum ---------------

    function getArbitrumProposal()
        public
        pure
        override
        returns (TimelockSimulation.action[] memory proposal)
    {
        proposal = new TimelockSimulation.action[](4);

        proposal[0].target = ArbitrumAddresses.VOLT_USDC_PSM;
        proposal[0].value = 0;
        proposal[0].arguments = abi.encodeWithSignature(
            "setOracle(address)",
            ArbitrumAddresses.ORACLE_PASS_THROUGH
        );
        proposal[0].description = "Set Oracle Pass Through on USDC PSM";

        proposal[1].target = ArbitrumAddresses.VOLT_DAI_PSM;
        proposal[1].value = 0;
        proposal[1].arguments = abi.encodeWithSignature(
            "setOracle(address)",
            ArbitrumAddresses.ORACLE_PASS_THROUGH
        );
        proposal[1].description = "Set Oracle Pass Through on DAI PSM";

        proposal[2].target = ArbitrumAddresses.VOLT_USDC_PSM;
        proposal[2].value = 0;
        proposal[2].arguments = abi.encodeWithSignature(
            "setMintFee(uint256)",
            0
        );
        proposal[2].description = "Set mint fee to 5 on USDC PSM";

        proposal[3].target = ArbitrumAddresses.VOLT_DAI_PSM;
        proposal[3].value = 0;
        proposal[3].arguments = abi.encodeWithSignature(
            "setMintFee(uint256)",
            0
        );
        proposal[3].description = "Set mint fee to 5 on DAI PSM";
    }

    /// @notice arbitrum usdc volt PSM
    PriceBoundPSM private immutable usdcPSM =
        PriceBoundPSM(ArbitrumAddresses.VOLT_USDC_PSM);

    /// @notice price of Volt on Arbitrum in USDC terms prior to the upgrade
    uint256 arbitrumStartingPrice;

    function arbitrumSetup() public override {
        vm.prank(ArbitrumAddresses.GOVERNOR);
        Core(ArbitrumAddresses.CORE).grantGovernor(
            ArbitrumAddresses.TIMELOCK_CONTROLLER
        );

        arbitrumStartingPrice = (usdcPSM.readOracle()).value;
    }

    /// assert all contracts have their correct number of roles now,
    /// and that the proper addresses have the correct role after the governance upgrade
    function arbitrumValidate() public override {
        _setupArbitrum(Core(ArbitrumAddresses.CORE));
        testRoleArity();

        _setupArbitrum(Core(ArbitrumAddresses.CORE));
        testRoleAddresses(Core(ArbitrumAddresses.CORE));

        uint256 arbitrumEndingPrice = (usdcPSM.readOracle()).value;
        /// maximum deviation of new oracle and regular oracle is 10 basis points
        assertApproxEq(
            arbitrumStartingPrice.toInt256(),
            arbitrumEndingPrice.toInt256(),
            10
        );
    }
}
