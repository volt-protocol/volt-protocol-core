pragma solidity =0.8.13;

import {Vm} from "./../utils/Vm.sol";
import {ICore} from "../../../core/ICore.sol";
import {DSTest} from "./../utils/DSTest.sol";
import {TribeRoles} from "../../../core/TribeRoles.sol";
import {PCVGuardAdmin} from "../../../pcv/PCVGuardAdmin.sol";
import {MockERC20, IERC20} from "../../../mock/MockERC20.sol";
import {ERC20HoldingPCVDeposit} from "../../../pcv/ERC20HoldingPCVDeposit.sol";
import {getCore, getAddresses, VoltTestAddresses} from "./../utils/Fixtures.sol";

contract UnitTestERC20HoldingsPCVDeposit is DSTest {
    ICore private core;

    ERC20HoldingPCVDeposit private erc20HoldingDeposit;

    MockERC20 private token;

    Vm public constant vm = Vm(HEVM_ADDRESS);

    function setUp() public {
        core = getCore();
        token = new MockERC20();

        erc20HoldingDeposit = new ERC20HoldingPCVDeposit(
            address(core),
            IERC20(address(token))
        );
    }

    function testWrapEthFailsWhenNotOnMainnetOrArbitrum() public {
        vm.deal(address(erc20HoldingDeposit), 10 ether); /// deal some eth
        vm.expectRevert("Can only wrap eth on mainnet and arbitrum");
        erc20HoldingDeposit.wrapETH();
    }
}
