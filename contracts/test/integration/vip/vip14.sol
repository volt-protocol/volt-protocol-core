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
import {IPCVDeposit} from "../../../pcv/IPCVDeposit.sol";
import {ERC20Skimmer} from "../../../pcv/utils/ERC20Skimmer.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {OraclePassThrough} from "../../../oracle/OraclePassThrough.sol";
import {CompoundPCVRouter} from "../../../pcv/compound/CompoundPCVRouter.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";
import {ITimelockSimulation} from "../utils/ITimelockSimulation.sol";
import {CompositeChainlinkOracleWrapper} from "../../../oracle/CompositeChainlinkOracleWrapper.sol";

contract vip14 is DSTest, IVIP {
    using SafeERC20 for IERC20;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    address private dai = MainnetAddresses.DAI;
    address private fei = MainnetAddresses.FEI;
    address private usdc = MainnetAddresses.USDC;
    address private core = MainnetAddresses.CORE;

    PegStabilityModule public immutable compPSM;

    ERC20Skimmer public immutable erc20Skimmer;

    CompositeChainlinkOracleWrapper public immutable oracle;

    OraclePassThrough private mainnetOPT =
        OraclePassThrough(MainnetAddresses.ORACLE_PASS_THROUGH);

    ITimelockSimulation.action[] private mainnetProposal;

    address public immutable compoundPCVRouter =
        MainnetAddresses.COMPOUND_PCV_ROUTER;

    CompoundPCVRouter public immutable router =
        CompoundPCVRouter(MainnetAddresses.COMPOUND_PCV_ROUTER);

    constructor() {
        oracle = new CompositeChainlinkOracleWrapper(
            core,
            MainnetAddresses.CHAINLINK_COMP_ORACLE_ADDRESS,
            mainnetOPT
        );

        PegStabilityModule.OracleParams memory oracleParams;

        oracleParams = PegStabilityModule.OracleParams({
            coreAddress: address(core),
            oracleAddress: address(oracle),
            backupOracle: address(0),
            decimalsNormalizer: 0,
            doInvert: true
        });

        compPSM = new PegStabilityModule(
            oracleParams,
            0,
            0,
            type(uint256).max,
            10_000e18, /// garbage value
            10_000_000e18, /// garbage value
            IERC20(MainnetAddresses.COMP),
            IPCVDeposit(address(1))
        );

        erc20Skimmer = new ERC20Skimmer(
            core,
            address(compPSM),
            MainnetAddresses.COMP
        );

        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: address(compPSM),
                arguments: abi.encodeWithSignature(
                    "pauseMint()",
                    address(compPSM)
                ),
                description: "Pause sale of COMP to this PSM"
            })
        );
        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: MainnetAddresses.CORE,
                arguments: abi.encodeWithSignature(
                    "grantPCVController(address)",
                    address(erc20Skimmer)
                ),
                description: "Grant COMP Skimmer ERC20Allocator Role"
            })
        );
        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: address(erc20Skimmer),
                arguments: abi.encodeWithSignature(
                    "addDeposit(address)",
                    MainnetAddresses.COMPOUND_DAI_PCV_DEPOSIT
                ),
                description: "Add Compound DAI PCV Deposit to COMP Skimmer"
            })
        );
        mainnetProposal.push(
            ITimelockSimulation.action({
                value: 0,
                target: address(erc20Skimmer),
                arguments: abi.encodeWithSignature(
                    "addDeposit(address)",
                    MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT
                ),
                description: "Add Compound USDC PCV Deposit to COMP Skimmer"
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

    /// assert core addresses are set correctly
    /// assert erc20 skimmer is pcv controller
    /// assert dai and usdc compound pcv deposit are in whitelist
    /// assert target and token are properly set on erc20 skimmer
    /// assert composite chainlink oracle points to correct oracle pass through
    function mainnetValidate() public override {
        assertEq(address(compPSM.core()), core);
        assertEq(address(erc20Skimmer.core()), core);
        assertEq(address(oracle.core()), core);

        assertTrue(Core(core).isPCVController(address(erc20Skimmer)));

        assertTrue(
            erc20Skimmer.isDepositWhitelisted(
                MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT
            )
        );
        assertTrue(
            erc20Skimmer.isDepositWhitelisted(
                MainnetAddresses.COMPOUND_DAI_PCV_DEPOSIT
            )
        );

        assertEq(address(erc20Skimmer.target()), address(compPSM));
        assertEq(address(erc20Skimmer.token()), MainnetAddresses.COMP);

        assertEq(address(oracle.oraclePassThrough()), address(mainnetOPT));
    }

    function getArbitrumProposal()
        public
        view
        override
        returns (ITimelockSimulation.action[] memory)
    {
        revert("No Arbitrum proposal");
    }

    function arbitrumSetup() public override {
        revert("No Arbitrum proposal");
    }

    /// assert oracle pass through is pointing to correct volt system oracle
    function arbitrumValidate() public override {
        revert("No Arbitrum proposal");
    }
}
