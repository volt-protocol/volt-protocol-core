pragma solidity =0.8.13;

import {Comptroller} from "./Comptroller.sol";

interface CToken {
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function isCToken() external view returns (bool);

    function isCEther() external view returns (bool);

    function comptroller() external view returns (Comptroller);
}
