pragma solidity =0.8.13;

import {Test} from "../../../../forge-std/src/Test.sol";
import {IProposal} from "./IProposal.sol";

abstract contract Proposal is IProposal, Test {
    bool public DEBUG = true;

    function setDebug(bool value) external {
        DEBUG = value;
    }
}
