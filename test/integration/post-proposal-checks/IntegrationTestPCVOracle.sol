// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {PostProposalCheck} from "@test/integration/post-proposal-checks/PostProposalCheck.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CoreV2} from "@voltprotocol/core/CoreV2.sol";
import {VoltV2} from "@voltprotocol/volt/VoltV2.sol";
import {PCVOracle} from "@voltprotocol/oracle/PCVOracle.sol";
import {IPCVOracle} from "@voltprotocol/oracle/IPCVOracle.sol";
import {PCVGuardian} from "@voltprotocol/pcv/PCVGuardian.sol";
import {GenericCallMock} from "@test/mock/GenericCallMock.sol";
import {NonCustodialPSM} from "@voltprotocol/peg/NonCustodialPSM.sol";

contract IntegrationTestPCVOracle is PostProposalCheck {
    CoreV2 private core;
    IERC20 private dai;
    VoltV2 private volt;
    address private grlm;
    PCVOracle private pcvOracle;
    NonCustodialPSM private daipsm;
    PCVGuardian private pcvGuardian;
    address private morphoDaiPCVDeposit;

    function setUp() public override {
        super.setUp();

        core = CoreV2(addresses.mainnet("CORE"));
        dai = IERC20(addresses.mainnet("DAI"));
        volt = VoltV2(addresses.mainnet("VOLT"));
        grlm = addresses.mainnet("GLOBAL_RATE_LIMITED_MINTER");
        morphoDaiPCVDeposit = addresses.mainnet(
            "PCV_DEPOSIT_MORPHO_COMPOUND_DAI"
        );
        daipsm = NonCustodialPSM(addresses.mainnet("PSM_NONCUSTODIAL_DAI"));
        pcvOracle = PCVOracle(addresses.mainnet("PCV_ORACLE"));
        pcvGuardian = PCVGuardian(addresses.mainnet("PCV_GUARDIAN"));
    }

    // check that we can read the pcv and it does not revert
    function testReadPcv() public {
        uint256 totalPcv = pcvOracle.getTotalPcv();
        assertTrue(totalPcv > 0, "Zero PCV");
    }

    // check that we can unset the PCVOracle in Core
    // and that it doesn't break PCV movements (only disables accounting).
    function testUnsetPcvOracle() public {
        address multisig = addresses.mainnet("GOVERNOR");

        GenericCallMock mock = new GenericCallMock();

        mock.setResponseToCall(
            address(0),
            "",
            abi.encode(true),
            bytes4(keccak256("isVenue(address)"))
        );

        mock.setResponseToCall(
            address(0),
            "",
            abi.encode(uint256(0)),
            bytes4(keccak256("lastRecordedPCVRaw(address)"))
        );

        vm.prank(multisig);
        core.setPCVOracle(IPCVOracle(address(mock)));

        vm.prank(multisig);
        pcvGuardian.withdrawToSafeAddress(morphoDaiPCVDeposit, 100e18);

        // No revert & PCV moved
        assertEq(dai.balanceOf(pcvGuardian.safeAddress()), 100e18);

        // User redeems
        vm.prank(grlm);
        volt.mint(address(this), 100e18);
        volt.approve(address(daipsm), 100e18);
        daipsm.redeem(address(this), 100e18, 104e18);
        assertGt(dai.balanceOf(address(this)), 104e18);
    }
}
