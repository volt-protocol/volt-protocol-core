pragma solidity ^0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Vm} from "../../../unit/utils/Vm.sol";
import {DSTest} from "../../../unit/utils/DSTest.sol";
import {ERC20HoldingPCVDeposit} from "../../../../pcv/ERC20HoldingPCVDeposit.sol";
import {CompoundPCVDepositV2} from "../../../../pcv/compound/CompoundPCVDepositV2.sol";
import {Core} from "../../../../core/Core.sol";
import {MockERC20} from "../../../../mock/MockERC20.sol";
import {MainnetAddresses} from "../../fixtures/MainnetAddresses.sol";
import {ArbitrumAddresses} from "../../fixtures/ArbitrumAddresses.sol";

contract ERC20HoldingPCVDepositIntegrationTest is DSTest {
    Vm public constant vm = Vm(HEVM_ADDRESS);

    Core private core = Core(MainnetAddresses.CORE);
    IERC20 private weth = IERC20(MainnetAddresses.WETH);
    IERC20 private volt = IERC20(MainnetAddresses.VOLT);
    CompoundPCVDepositV2 private pcvDeposit;

    function setUp() public {
        pcvDeposit = new CompoundPCVDepositV2(
            address(core),
            MainnetAddresses.CDAI
        );
    }

    function testCanDepositAndClaimComp() public {}

    /// @notice Validate can not deploy with VOLT mainnet address
    function testCanNotDeploy() public {
        vm.expectRevert(bytes("VOLT not supported"));
        new ERC20HoldingPCVDeposit(address(core), volt,address(0));
    }
}
