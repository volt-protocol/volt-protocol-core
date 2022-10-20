pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockMorpho {
    IERC20 public immutable token;
    mapping(address => uint256) public balances;

    constructor(IERC20 _token) {
        token = _token;
    }

    function withdraw(address, uint256 amount) external {
        balances[msg.sender] -= amount;
        token.transfer(msg.sender, amount);
    }

    function supply(
        address,
        address recipient,
        uint256 amountUnderlying
    ) external {
        token.transferFrom(msg.sender, address(this), amountUnderlying);
        balances[recipient] += amountUnderlying;
    }

    function setBalance(address to, uint256 amount) external {
        balances[to] = amount;
    }

    function claimRewards(address cToken, bool swapForMorpho)
        external
        returns (uint256)
    {}

    function updateP2PIndexes(address) external {}

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
