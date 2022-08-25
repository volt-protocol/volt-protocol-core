pragma solidity =0.8.13;

import {CToken} from "./CToken.sol";

interface Comptroller {
    function claimComp(address holder) external;

    function claimComp(address holder, CToken[] memory cTokens) external;

    function claimComp(
        address[] memory holders,
        CToken[] memory cTokens,
        bool borrowers,
        bool suppliers
    ) external;
}
