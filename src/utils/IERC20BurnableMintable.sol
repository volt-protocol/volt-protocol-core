pragma solidity =0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20BurnableMintable is IERC20 {
    function burnFrom(address account, uint256 amount) external;

    function burn(uint256 amount) external;

    function mint(address account, uint256 amount) external;
}
