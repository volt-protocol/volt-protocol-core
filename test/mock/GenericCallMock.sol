// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

contract GenericCallMock {
    struct ResponseData {
        address target;
        bytes callData;
        bytes returnData;
    }

    mapping(bytes4 => ResponseData) public response;

    function setResponseToCall(
        address target,
        bytes calldata callData,
        bytes calldata returnData,
        bytes4 functionSig
    ) external {
        ResponseData memory responseInfo = ResponseData({
            target: target,
            callData: callData,
            returnData: returnData
        });

        response[functionSig] = responseInfo;
    }

    fallback(bytes calldata) external returns (bytes memory returnData) {
        bytes4 functionSignature;

        assembly {
            functionSignature := calldataload(0) /// grab first 4 bytes of calldata
        }

        if (
            response[functionSignature].callData.length != 0 ||
            response[functionSignature].returnData.length != 0
        ) {
            ResponseData memory responseInfo = response[functionSignature];

            address target = responseInfo.target;
            returnData = responseInfo.returnData;
            bytes memory callData = responseInfo.callData;

            /// external call is optional
            if (target != address(0)) {
                (bool success, ) = target.call(callData);
                if (!success) {
                    assembly ("memory-safe") {
                        let ptr := mload(0x40)

                        // Copy the returned data.
                        returndatacopy(ptr, 0, returndatasize())

                        revert(ptr, returndatasize())
                    }
                }
            }
        }
    }
}
