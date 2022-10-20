pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MorphoCompoundPCVDeposit} from "contracts/pcv/morpho/MorphoCompoundPCVDeposit.sol";

contract MockMorphoMaliciousReentrancy {
    IERC20 public immutable token;
    mapping(address => uint256) public balances;
    MorphoCompoundPCVDeposit public morphoCompoundPCVDeposit;

    constructor(IERC20 _token) {
        token = _token;
    }

    function setMorphoCompoundPCVDeposit(address deposit) external {
        morphoCompoundPCVDeposit = MorphoCompoundPCVDeposit(deposit);
    }

    function withdraw(address, uint256) external {
        morphoCompoundPCVDeposit.accrue();
    }

    function supply(
        address,
        address,
        uint256
    ) external {
        morphoCompoundPCVDeposit.deposit();
    }

    function setBalance(address to, uint256 amount) external {
        balances[to] = amount;
    }

    function claimRewards(address cToken, bool swapForMorpho)
        external
        returns (uint256)
    {}

    function updateP2PIndexes(address) external {
        morphoCompoundPCVDeposit.accrue();
    }

    function getCurrentSupplyBalanceInOf(address, address _user)
        external
        view
        returns (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        )
    {
        return (0, 0, balances[_user]);
    }
}
