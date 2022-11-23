pragma solidity 0.8.13;

import "./MockERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IERC4626} from "../pcv/ERC4626/IERC4626.sol";
import "../pcv/ERC4626/ERC4626PCVDeposit.sol";

contract MockERC4626VaultMaliciousReentrancy {
    IERC20 public immutable token;
    mapping(address => uint256) public balances;
    ERC4626PCVDeposit public erc4626vaultPCVDeposit;

    constructor(MockERC20 _token) {
        token = _token;
    }

    function asset() external view returns (address) {
        return address(token);
    }

    function setERC4626PCVDeposit(address pcvDeposit) external {
        erc4626vaultPCVDeposit = ERC4626PCVDeposit(pcvDeposit);
    }

    function balanceOf(address) external {
        erc4626vaultPCVDeposit.accrue();
    }

    // try to reenter withdraw or withdraw max with 50% chance
    function withdraw(address, uint256 amount) external {
        if(amount % 2 == 0) {
            erc4626vaultPCVDeposit.withdraw(address(this), amount);
        }
        else {
            erc4626vaultPCVDeposit.withdrawMax(address(this));
        }
    }

    function deposit(uint256, address) external {
        erc4626vaultPCVDeposit.deposit();
    }
}
