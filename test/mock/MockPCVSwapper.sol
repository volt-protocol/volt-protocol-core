pragma solidity 0.8.13;

import {console} from "@forge-std/console.sol";

import {MockERC20} from "@test/mock/MockERC20.sol";
import {IPCVSwapper} from "@voltprotocol/pcv/IPCVSwapper.sol";

contract MockPCVSwapper is IPCVSwapper {
    MockERC20 public tokenIn;
    MockERC20 public tokenOut;
    uint256 public exchangeRate = 1e18;

    constructor(MockERC20 _tokenIn, MockERC20 _tokenOut) {
        tokenIn = _tokenIn;
        tokenOut = _tokenOut;
    }

    function mockSetExchangeRate(uint256 rate) external {
        exchangeRate = rate;
    }

    function canSwap(
        address assetIn,
        address assetOut
    ) public view returns (bool) {
        return
            (address(tokenIn) == assetIn && address(tokenOut) == assetOut) ||
            (address(tokenIn) == assetOut && address(tokenOut) == assetIn);
    }

    function swap(
        address assetIn,
        address assetOut,
        address destination
    ) external returns (uint256) {
        require(canSwap(assetIn, assetOut), "MockPCVSwapper: invalid swap");

        uint256 amountIn = MockERC20(assetIn).balanceOf(address(this));

        /// if regular flow, do regular rate, otherwise reverse rate
        uint256 amountOut = address(tokenIn) == assetIn
            ? (amountIn * exchangeRate) / 1e18
            : ((amountIn * 1e18) / exchangeRate);

        console.log("amountIn: ", amountIn);
        console.log("amountOut: ", amountOut);

        MockERC20(assetIn).mockBurn(address(this), amountIn);
        MockERC20(assetOut).mint(destination, amountOut);

        emit Swap(assetIn, assetOut, destination, amountIn, amountOut);

        return amountOut;
    }
}
