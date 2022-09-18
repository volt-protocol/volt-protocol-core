pragma solidity ^0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Vm} from "../../unit/utils/Vm.sol";
import {DSTest} from "../../unit/utils/DSTest.sol";
import {ERC20HoldingPCVDeposit} from "../../../pcv/ERC20HoldingPCVDeposit.sol";
import {Core} from "../../../core/Core.sol";
import {MockERC20} from "../../../mock/MockERC20.sol";
import {MainnetAddresses} from "../fixtures/MainnetAddresses.sol";
import {ArbitrumAddresses} from "../fixtures/ArbitrumAddresses.sol";

contract ERC20HoldingPCVDepositIntegrationTest is DSTest {
    Vm public constant vm = Vm(HEVM_ADDRESS);
    address payable receiver = payable(address(3));

    Core core = Core(MainnetAddresses.CORE);
    IERC20 weth = IERC20(MainnetAddresses.WETH);
    IERC20 volt = IERC20(MainnetAddresses.VOLT);
    IERC20 arbitrumVolt = IERC20(ArbitrumAddresses.VOLT);

    uint256 amount = 2 ether;

    /// @notice Validate that can wrap ETH to WETH
    function testCanWrapEth() public {
        ERC20HoldingPCVDeposit wethDeposit = new ERC20HoldingPCVDeposit(
            address(core),
            weth,
            address(0)
        );

        // Forking mainnet, Foundry uses same address to deploy for all users. This contract gets deployed to
        // an EOA which already has funds
        uint256 initialEthBalance = address(wethDeposit).balance;
        assertEq(wethDeposit.balance(), 0); // will not currently have WETH

        payable(address(wethDeposit)).transfer(amount);
        assertEq(address(wethDeposit).balance, amount + initialEthBalance);
        wethDeposit.wrapETH();
        assertEq(address(wethDeposit).balance, 0);

        // Validate WETH balance is reported correctly for all balance functions
        assertEq(
            weth.balanceOf(address(wethDeposit)),
            amount + initialEthBalance
        );
        assertEq(wethDeposit.balance(), amount + initialEthBalance);

        (uint256 resistantBalance, uint256 feiBalance) = wethDeposit
            .resistantBalanceAndVolt();
        assertEq(resistantBalance, amount + initialEthBalance);
        assertEq(feiBalance, 0);
    }

    /// @notice Validate that can withdraw ETH that was wrapped to WETH
    function testCanWithdraWrappedEth() public {
        ERC20HoldingPCVDeposit wethDeposit = new ERC20HoldingPCVDeposit(
            address(core),
            weth,address(0)
        );
        uint256 initialEthBalance = address(wethDeposit).balance;
        assertEq(wethDeposit.balance(), 0);

        // Transfer ETH to the deposit and wrap it
        payable(address(wethDeposit)).transfer(amount);
        wethDeposit.wrapETH();

        // Withdraw all wrapped ETH and verify balances report correctly
        vm.prank(MainnetAddresses.GOVERNOR);
        wethDeposit.withdrawERC20(
            MainnetAddresses.WETH,
            receiver,
            amount + initialEthBalance
        );

        assertEq(weth.balanceOf(receiver), amount + initialEthBalance);

        assertEq(weth.balanceOf(address(wethDeposit)), 0);
        assertEq(wethDeposit.balance(), 0);
        (uint256 resistantBalance, uint256 feiBalance) = wethDeposit
            .resistantBalanceAndVolt();
        assertEq(resistantBalance, 0);
        assertEq(feiBalance, 0);
    }

    /// @notice Validate can not deploy with VOLT mainnet address
    function testCanNotDeployForVoltMainnet() public {
        vm.expectRevert(bytes("VOLT not supported"));
        new ERC20HoldingPCVDeposit(address(core), volt,address(0));
    }

    /// @notice Validate can not deploy with VOLT arbitrum address
    function testCanNotDeployForVoltArbitrum() public {
        vm.expectRevert(bytes("VOLT not supported"));
        new ERC20HoldingPCVDeposit(address(core), arbitrumVolt,address(0));
    }
}
