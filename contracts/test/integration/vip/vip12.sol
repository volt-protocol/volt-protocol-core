//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {Vm} from "./../../unit/utils/Vm.sol";
import {Core} from "../../../core/Core.sol";
import {IVIP} from "./IVIP.sol";
import {DSTest} from "./../../unit/utils/DSTest.sol";
import {PCVGuardian} from "../../../pcv/PCVGuardian.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {OraclePassThrough} from "../../../oracle/OraclePassThrough.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";
import {ITimelockSimulation} from "../utils/ITimelockSimulation.sol";
import {CompoundPCVRouter} from "../../../pcv/compound/CompoundPCVRouter.sol";

contract vip12 is DSTest, IVIP {
    using SafeERC20 for IERC20;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    address private dai = MainnetAddresses.DAI;
    address private fei = MainnetAddresses.FEI;
    address private usdc = MainnetAddresses.USDC;
    address private core = MainnetAddresses.CORE;

    OraclePassThrough private mainnetOPT =
        OraclePassThrough(MainnetAddresses.ORACLE_PASS_THROUGH);

    ITimelockSimulation.action[] private mainnetProposal;
    address public immutable compoundPCVRouter =
        MainnetAddresses.COMPOUND_PCV_ROUTER;
    CompoundPCVRouter public immutable router =
        CompoundPCVRouter(MainnetAddresses.COMPOUND_PCV_ROUTER);

    constructor() {
        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.CORE,
                arguments: abi.encodeWithSignature(
                    "grantPCVController(address)",
                    compoundPCVRouter
                ),
                description: "Grant Compound PCV Router the PCV Controller Role"
            })
        );
    }

    function getMainnetProposal()
        public
        view
        override
        returns (ITimelockSimulation.action[] memory)
    {
        return mainnetProposal;
    }

    function mainnetSetup() public override {}

    /// assert compound pcv router has pcv controller role
    /// assert all variables are correclty set in compound pcv router
    function mainnetValidate() public override {
        assertTrue(Core(core).isPCVController(compoundPCVRouter));

        assertEq(address(router.core()), address(core));
        assertEq(address(router.USDC()), usdc);
        assertEq(address(router.DAI()), dai);
        assertEq(
            address(router.daiPcvDeposit()),
            MainnetAddresses.COMPOUND_DAI_PCV_DEPOSIT
        );
        assertEq(
            address(router.usdcPcvDeposit()),
            MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT
        );
        assertEq(address(router.daiPSM()), MainnetAddresses.MAKER_DAI_USDC_PSM);
        assertEq(address(router.GEM_JOIN()), MainnetAddresses.GEM_JOIN);
    }

    function getArbitrumProposal()
        public
        pure
        override
        returns (ITimelockSimulation.action[] memory)
    {
        revert("No Arbitrum proposal");
    }

    function arbitrumSetup() public pure override {
        revert("No Arbitrum proposal");
    }

    /// assert oracle pass through is pointing to correct volt system oracle
    function arbitrumValidate() public pure override {
        revert("No Arbitrum proposal");
    }
}
