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
import {ArbitrumAddresses} from "../fixtures/ArbitrumAddresses.sol";
import {PegStabilityModule} from "../../../peg/PegStabilityModule.sol";
import {ITimelockSimulation} from "../utils/ITimelockSimulation.sol";
import {ERC20CompoundPCVDeposit} from "../../../pcv/compound/ERC20CompoundPCVDeposit.sol";

contract vip9 is DSTest, IVIP {
    using SafeERC20 for IERC20;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    address private fei = MainnetAddresses.FEI;
    address private core = MainnetAddresses.CORE;

    ERC20CompoundPCVDeposit private daiDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_DAI_PCV_DEPOSIT);
    ERC20CompoundPCVDeposit private feiDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_FEI_PCV_DEPOSIT);
    ERC20CompoundPCVDeposit private usdcDeposit =
        ERC20CompoundPCVDeposit(MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT);

    function getMainnetProposal()
        public
        pure
        override
        returns (ITimelockSimulation.action[] memory proposal)
    {
        proposal = new ITimelockSimulation.action[](1);

        address[] memory toWhitelist = new address[](3);
        toWhitelist[0] = MainnetAddresses.COMPOUND_DAI_PCV_DEPOSIT;
        toWhitelist[1] = MainnetAddresses.COMPOUND_FEI_PCV_DEPOSIT;
        toWhitelist[2] = MainnetAddresses.COMPOUND_USDC_PCV_DEPOSIT;

        proposal[0].target = MainnetAddresses.PCV_GUARDIAN;
        proposal[0].value = 0;
        proposal[0].arguments = abi.encodeWithSignature(
            "addWhitelistAddresses(address[])",
            toWhitelist
        );
        proposal[0]
            .description = "Add DAI, FEI, and USDC Compound PCV Deposit to PCV Guardian";
    }

    function mainnetSetup() public override {
        uint256 tokenBalance = IERC20(fei).balanceOf(MainnetAddresses.GOVERNOR);
        vm.prank(MainnetAddresses.GOVERNOR);
        IERC20(fei).transfer(address(feiDeposit), tokenBalance);
        feiDeposit.deposit();
    }

    function mainnetValidate() public override {
        assertTrue(
            PCVGuardian(MainnetAddresses.PCV_GUARDIAN).isWhitelistAddress(
                address(daiDeposit)
            )
        );
        assertTrue(
            PCVGuardian(MainnetAddresses.PCV_GUARDIAN).isWhitelistAddress(
                address(feiDeposit)
            )
        );
        assertTrue(
            PCVGuardian(MainnetAddresses.PCV_GUARDIAN).isWhitelistAddress(
                address(usdcDeposit)
            )
        );
        assertEq(address(daiDeposit.core()), core);
        assertEq(address(feiDeposit.core()), core);
        assertEq(address(usdcDeposit.core()), core);
        assertEq(address(daiDeposit.cToken()), address(MainnetAddresses.CDAI));
        assertEq(address(feiDeposit.cToken()), address(MainnetAddresses.CFEI));
        assertEq(
            address(usdcDeposit.cToken()),
            address(MainnetAddresses.CUSDC)
        );
        assertEq(address(daiDeposit.token()), address(MainnetAddresses.DAI));
        assertEq(address(feiDeposit.token()), address(MainnetAddresses.FEI));
        assertEq(address(usdcDeposit.token()), address(MainnetAddresses.USDC));

        uint256 tokenBalance = IERC20(fei).balanceOf(
            MainnetAddresses.FEI_DAI_PSM
        );
        vm.prank(MainnetAddresses.FEI_DAI_PSM);
        IERC20(fei).transfer(address(feiDeposit), tokenBalance);
        feiDeposit.deposit();
    }

    /// prevent errors by reverting on arbitrum proposal functions being called on this VIP
    function getArbitrumProposal()
        public
        pure
        override
        returns (ITimelockSimulation.action[] memory)
    {
        revert("no arbitrum proposal");
    }

    function arbitrumSetup() public pure override {
        revert("no arbitrum proposal");
    }

    function arbitrumValidate() public pure override {
        revert("no arbitrum proposal");
    }
}
