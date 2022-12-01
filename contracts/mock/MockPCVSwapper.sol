pragma solidity 0.8.13;

import {MockERC20} from "./MockERC20.sol";
import {IPCVSwapper} from "../pcv/IPCVSwapper.sol";

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
    ) external view returns (bool) {
        return address(tokenIn) == assetIn && address(tokenOut) == assetOut;
    }

    function swap(
        address assetIn,
        address assetOut,
        address destination
    ) external returns (uint256) {
        require(assetIn == address(tokenIn), "MockPCVSwapper: invalid assetIn");
        require(
            assetOut == address(tokenOut),
            "MockPCVSwapper: invalid assetOut"
        );

        uint256 amountIn = tokenIn.balanceOf(address(this));
        uint256 amountOut = (amountIn * exchangeRate) / 1e18;
        tokenIn.mockBurn(address(this), amountIn);
        tokenOut.mint(destination, amountOut);

        emit Swap(assetIn, assetOut, destination, amountIn, amountOut);

        return amountOut;
    }
}
