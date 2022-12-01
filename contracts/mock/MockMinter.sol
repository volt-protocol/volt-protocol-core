pragma solidity 0.8.13;

import {IGlobalRateLimitedMinter} from "../limiter/IGlobalRateLimitedMinter.sol";
import {CoreRefV2} from "../refs/CoreRefV2.sol";

contract MockMinter is CoreRefV2 {
    IGlobalRateLimitedMinter public grlm;

    constructor(address core, address _grlm) CoreRefV2(core) {
        grlm = IGlobalRateLimitedMinter(_grlm);
    }

    function mint(address to, uint256 amount) external globalLock(1) {
        grlm.mintVolt(to, amount);
    }

    function replenishBuffer(uint256 amount) external globalLock(1) {
        grlm.replenishBuffer(amount);
    }
}
