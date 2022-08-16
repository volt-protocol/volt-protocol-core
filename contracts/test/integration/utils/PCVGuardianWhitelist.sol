pragma solidity =0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPCVGuardian} from "../../../pcv/IPCVGuardian.sol";
import {ITimelockSimulation} from "./ITimelockSimulation.sol";
import {IPermissions} from "./../../../core/IPermissions.sol";

/// Only allow approvals and transfers of PCV to addresses in PCV Guardian,
/// and only allow granting PCV controllers if they are subsequently added to
/// the PCV Guardian
contract PCVGuardianWhitelist {
    mapping(bytes4 => bool) public functionDetectors;

    constructor() {
        functionDetectors[IERC20.transfer.selector] = true;
        functionDetectors[IERC20.approve.selector] = true;
        functionDetectors[IPermissions.grantPCVController.selector] = true;
    }

    /// @notice function to verify actions and ensure that granting a PCV Controller or transferring assets
    /// only happens to addresses that are on the PCV Guardian whitelist
    function verifyAction(
        ITimelockSimulation.action[] memory proposal,
        IPCVGuardian guardian
    ) public view {
        uint256 proposalLength = proposal.length;
        for (uint256 i = 0; i < proposalLength; i++) {
            bytes4 functionSig = bytesToBytes4(proposal[i].arguments);

            if (functionDetectors[functionSig]) {
                address recipient;
                bytes memory payload = proposal[i].arguments;
                assembly {
                    recipient := mload(add(payload, 36))
                }

                if (!guardian.isWhitelistAddress(recipient)) {
                    revert(
                        string(
                            abi.encodePacked(
                                "Address ",
                                toString(abi.encodePacked(recipient)),
                                " not in PCV Guardian whitelist"
                            )
                        )
                    );
                }
            }
        }
    }

    /// @notice function to grab the first 4 bytes of calldata payload
    function bytesToBytes4(bytes memory toSlice)
        public
        pure
        returns (bytes4 functionSignature)
    {
        if (toSlice.length < 4) {
            return bytes4(0);
        }

        assembly {
            functionSignature := mload(add(toSlice, 0x20))
        }
    }

    /// Credit ethereum stackexchange https://ethereum.stackexchange.com/a/58341
    function toString(bytes memory data) public pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < data.length; i++) {
            str[2 + i * 2] = alphabet[uint256(uint8(data[i] >> 4))];
            str[3 + i * 2] = alphabet[uint256(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }
}
