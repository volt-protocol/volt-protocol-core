pragma solidity =0.8.13;

import {Vm} from "@forge-std/Vm.sol";
import {ICore} from "@voltprotocol/v1/ICore.sol";
import {Test} from "@forge-std/Test.sol";
import {MockERC20} from "@test/mock/MockERC20.sol";
import {VoltRoles} from "@voltprotocol/core/VoltRoles.sol";
import {IPCVDeposit} from "@voltprotocol/pcv/IPCVDeposit.sol";
import {MockERC20, IERC20} from "@test/mock/MockERC20.sol";
import {ERC20HoldingPCVDeposit} from "@test/mock/ERC20HoldingPCVDeposit.sol";
import {TestAddresses as addresses} from "@test/unit/utils/TestAddresses.sol";
import {getCore} from "@test/unit/utils/Fixtures.sol";

contract UnitTestERC20HoldingsPCVDeposit is Test {
    event Deposit(address indexed _from, uint256 _amount);

    ICore private core;

    ERC20HoldingPCVDeposit private erc20HoldingDeposit;

    /// @notice token to deposit
    MockERC20 private token;

    function setUp() public {
        core = getCore();
        token = new MockERC20();

        erc20HoldingDeposit = new ERC20HoldingPCVDeposit(
            address(core),
            IERC20(address(token)),
            address(0)
        );
    }

    function testWrapEthFailsWhenNotOnMainnetOrArbitrum() public {
        vm.deal(address(erc20HoldingDeposit), 10 ether); /// deal some eth
        vm.expectRevert(); /// call to address 0 fails
        erc20HoldingDeposit.wrapETH();
    }

    function testWithdrawAllSucceeds() public {
        uint256 tokenAmount = 10_000_000e18;
        token.mint(address(erc20HoldingDeposit), tokenAmount);

        assertEq(token.balanceOf(address(erc20HoldingDeposit)), tokenAmount);
        assertEq(token.balanceOf(address(this)), 0);

        vm.prank(addresses.governorAddress);
        erc20HoldingDeposit.withdrawAll(address(this));

        assertEq(token.balanceOf(address(this)), tokenAmount);
        assertEq(token.balanceOf(address(erc20HoldingDeposit)), 0);
    }

    function testWithdrawSucceeds() public {
        uint256 tokenAmount = 10_000_000e18;
        token.mint(address(erc20HoldingDeposit), tokenAmount);

        assertEq(token.balanceOf(address(erc20HoldingDeposit)), tokenAmount);
        assertEq(token.balanceOf(address(this)), 0);

        vm.prank(addresses.governorAddress);
        erc20HoldingDeposit.withdraw(address(this), tokenAmount);

        assertEq(token.balanceOf(address(this)), tokenAmount);
        assertEq(token.balanceOf(address(erc20HoldingDeposit)), 0);
    }

    function testWithdrawERC20Succeeds() public {
        uint256 tokenAmount = 10_000_000e18;
        token.mint(address(erc20HoldingDeposit), tokenAmount);

        assertEq(token.balanceOf(address(erc20HoldingDeposit)), tokenAmount);
        assertEq(token.balanceOf(address(this)), 0);

        vm.prank(addresses.pcvControllerAddress);
        erc20HoldingDeposit.withdrawERC20(
            address(token),
            address(this),
            tokenAmount
        );

        assertEq(token.balanceOf(address(this)), tokenAmount);
        assertEq(token.balanceOf(address(erc20HoldingDeposit)), 0);
    }

    function testWithdrawEthSucceeds() public {
        uint256 tokenAmount = 10_000_000e18;
        address payable recipient = payable(address(0x123456789));

        vm.deal(address(erc20HoldingDeposit), tokenAmount);

        assertEq(address(erc20HoldingDeposit).balance, tokenAmount);
        assertEq(recipient.balance, 0);

        vm.prank(addresses.pcvControllerAddress);
        erc20HoldingDeposit.withdrawETH(recipient, tokenAmount);

        assertEq(address(erc20HoldingDeposit).balance, 0);
        assertEq(recipient.balance, tokenAmount);
    }

    function testWithdrawERC20FailsNonPCVController() public {
        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        erc20HoldingDeposit.withdrawERC20(address(token), address(this), 0);
    }

    function testWithdrawAllFailsNonPCVController() public {
        vm.expectRevert("UNAUTHORIZED");
        erc20HoldingDeposit.withdrawAll(address(this));
    }

    function testWithdrawFailsNonPCVController() public {
        vm.expectRevert("UNAUTHORIZED");
        erc20HoldingDeposit.withdraw(address(this), 10);
    }

    function testWithdrawEthFailsNonPCVController() public {
        vm.expectRevert("CoreRef: Caller is not a PCV controller");
        erc20HoldingDeposit.withdrawETH(payable(address(this)), 10);
    }

    function testDepositNoOp() public {
        erc20HoldingDeposit.deposit();
    }

    function testDepositFailsOnPause() public {
        vm.prank(addresses.governorAddress);
        erc20HoldingDeposit.pause();

        vm.expectRevert("Pausable: paused");
        erc20HoldingDeposit.deposit();
    }
}
