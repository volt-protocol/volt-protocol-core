// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../external/Decimal.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBondingCurve {
    // ----------- Events -----------

    event ScaleUpdate(uint256 _scale);
        
    event TokenUpdate(address indexed _token);

    event BufferUpdate(uint256 _buffer);

    event DiscountUpdate(uint256 _discount);

    event IncentiveAmountUpdate(uint256 _incentiveAmount);

    event Purchase(address indexed _to, uint256 _amountIn, uint256 _amountOut);

    event Allocate(address indexed _caller, uint256 _amount);

    event Reset();
    
    // ----------- State changing Api -----------

    function purchase(address to, uint256 amountIn)
        external
        payable
        returns (uint256 amountOut);

    function allocate() external;

    // ----------- Governor only state changing api -----------

    function reset() external;

    function setBuffer(uint256 _buffer) external;

    function setDiscount(uint256 _discount) external;

    function setToken(address _token) external;

    function setScale(uint256 _scale) external;

    function setAllocation(
        address[] calldata pcvDeposits,
        uint256[] calldata ratios
    ) external;

    function setIncentiveAmount(uint256 _incentiveAmount) external;

    function setIncentiveFrequency(uint256 _frequency) external;

    // ----------- Getters -----------

    function getCurrentPrice() external view returns (Decimal.D256 memory);

    function getAverageUSDPrice(uint256 amountIn)
        external
        view
        returns (Decimal.D256 memory);

    function getAmountOut(uint256 amountIn)
        external
        view
        returns (uint256 amountOut);

    function scale() external view returns (uint256);

    function atScale() external view returns (bool);

    function buffer() external view returns (uint256);

    function discount() external view returns (uint256);

    function totalPurchased() external view returns (uint256);

    function balance() external view returns (uint256);

    function token() external view returns (IERC20);

    function incentiveAmount() external view returns (uint256);
}
