pragma solidity =0.8.13;

import {Addresses} from "../Addresses.sol";

interface IProposal {
    function name() external view returns (string memory);

    function setDebug(bool) external;

    function deploy(Addresses) external;

    function afterDeploy(Addresses, address) external;

    function run(Addresses, address) external;

    function teardown(Addresses, address) external;

    function validate(Addresses, address) external;
}
