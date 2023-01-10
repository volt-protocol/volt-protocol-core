pragma solidity 0.8.13;

import "hardhat/console.sol";
import {Test} from "../../forge-std/src/Test.sol";

contract GenericMock is Test {
    struct ResponseData {
        address target;
        bytes payload;
        bytes returnData;
    }

    mapping(address => ResponseData) public response;
    mapping(address => mapping(bytes4 => ResponseData)) public responseToCall;

    function setResponse(
        address sender,
        address target,
        bytes calldata payload,
        bytes calldata returnData
    ) external {
        ResponseData memory callResponse = ResponseData({
            target: target,
            payload: payload,
            returnData: returnData
        });
        response[sender] = callResponse;
    }

    function setResponseToCall(
        address sender,
        address target,
        bytes calldata payload,
        bytes calldata returnData,
        bytes4 functionSig
    ) external {
        emit log_bytes(returnData);

        ResponseData memory callResponse = ResponseData({
            target: target,
            payload: payload,
            returnData: returnData
        });

        responseToCall[sender][functionSig] = callResponse;
    }

    fallback() external {
        bytes4 functionSignature;

        assembly {
            functionSignature := calldataload(0) /// grab first 4 bytes of calldata
        }

        if (
            responseToCall[msg.sender][functionSignature].payload.length != 0 ||
            responseToCall[msg.sender][functionSignature].returnData.length != 0
        ) {
            console.log(
                "responseToCall[msg.sender][functionSignature].returnData.length",
                responseToCall[msg.sender][functionSignature].returnData.length
            );
            console.log("handling response to call");
            ResponseData memory callResponse = responseToCall[msg.sender][
                functionSignature
            ];
            console.log("handling response to call 0");
            bytes memory returnData = handleCallAndReturn(callResponse);
            console.log("handling response to call 1");

            address returnAddress;
            assembly {
                returnAddress := returnData
            }

            console.log("return bytes");
            emit log_bytes(returnData);
            emit log_bytes(
                responseToCall[msg.sender][functionSignature].returnData
            );

            assembly {
                let ptr := mload(0x40) /// grab the free memory pointer
                return(ptr, returnData)
            }
        } else if (
            response[msg.sender].payload.length != 0 ||
            response[msg.sender].returnData.length != 0
        ) {
            console.log("handling response");
            ResponseData memory callResponse = response[msg.sender];
            console.log("handling response 0");
            bytes memory returnData = handleCallAndReturn(callResponse);
            console.log("handling response 1");
            assembly {
                let ptr := mload(0x40) /// grab the free memory pointer
                return(ptr, returnData)
            }
        }
    }

    function handleCallAndReturn(
        ResponseData memory callResponse
    ) internal returns (bytes memory returnData) {
        console.log("handle call and return");

        bytes memory payload = callResponse.payload;
        returnData = callResponse.returnData;
        address target = callResponse.target;

        console.log("0");

        console.log("return data");
        emit log_bytes(returnData);

        console.log("payload");
        emit log_bytes(payload);

        console.log("target: ", target);

        if (uint160(target) != 0) {
            (bool success, ) = target.call(payload);
            success; // shhhh
        }
    }
}
