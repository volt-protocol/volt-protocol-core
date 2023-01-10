pragma solidity 0.8.13;

import "hardhat/console.sol";
import {Test} from "../../forge-std/src/Test.sol";

contract GenericReturnMock is Test {
    struct ResponseData {
        address target;
        bytes returnData;
    }

    mapping(bytes4 => bytes) public response;

    function setResponseToCall(
        bytes calldata returnData,
        bytes4 functionSig
    ) external {
        emit log_bytes(returnData);
        emit log_bytes(abi.encodePacked(functionSig));

        response[functionSig] = returnData;
    }

    fallback(bytes calldata) external returns (bytes memory) {
        bytes4 functionSignature;

        assembly {
            functionSignature := calldataload(0) /// grab first 4 bytes of calldata
        }

        if (response[functionSignature].length != 0) {
            console.log("handling response 0");
            bytes memory returnData = response[functionSignature];
            console.log("handling response 1");

            console.log("address: ", abi.decode(returnData, (address)));
            return returnData;
        }
    }
}
