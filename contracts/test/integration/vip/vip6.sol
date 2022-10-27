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

contract vip6 is DSTest, IVIP {
    using SafeCast for *;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    bool public ignore;

    /// --------------- Mainnet ---------------

    function getMainnetProposal()
        public
        pure
        override
        returns (ITimelockSimulation.action[] memory)
    {
        revert("no mainnet proposal");
    }

    function mainnetSetup() public override {
        if (false) {
            ignore = false;
        }
        revert("no mainnet proposal");
    }

    /// assert all contracts have their correct number of roles now,
    /// and that the proper addresses have the correct role after the governance upgrade
    function mainnetValidate() public override {
        if (false) {
            ignore = false;
        }
        revert("no mainnet proposal");
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
            "setMintFee(uint256)",
            0
        );
        proposal[0].description = "Set mint fee to 0 basis points on DAI PSM";

        proposal[1].target = ArbitrumAddresses.VOLT_DAI_PSM;
        proposal[1].value = 0;
        proposal[1].arguments = abi.encodeWithSignature(
            "setRedeemFee(uint256)",
            0
        );
        proposal[1].description = "Set redeem fee to 0 basis points on DAI PSM";

        proposal[2].target = ArbitrumAddresses.VOLT_USDC_PSM;
        proposal[2].value = 0;
        proposal[2].arguments = abi.encodeWithSignature(
            "setMintFee(uint256)",
            0
        );
        proposal[2].description = "Set mint fee to 0 basis points on USDC PSM";

        proposal[3].target = ArbitrumAddresses.VOLT_USDC_PSM;
        proposal[3].value = 0;
        proposal[3].arguments = abi.encodeWithSignature(
            "setRedeemFee(uint256)",
            0
        );
        proposal[3]
            .description = "Set redeem fee to 0 basis points on USDC PSM";
    }

    /// @notice arbitrum usdc volt PSM
    PriceBoundPSM private immutable usdcPSM =
        PriceBoundPSM(ArbitrumAddresses.VOLT_USDC_PSM);

    /// @notice arbitrum dai volt PSM
    PriceBoundPSM private immutable daiPSM =
        PriceBoundPSM(ArbitrumAddresses.VOLT_DAI_PSM);

    /// no-op
    function arbitrumSetup() public override {}

    function arbitrumValidate() public override {}
}
