// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Core, Volt, Vcon, IERC20} from "./Core.sol";
import {DSTest} from "./../test/utils/DSTest.sol";

/// @notice helper contract that is needed to properly wire up the Core, VCON and VOLT token
/// this contract is needed as Core stores an immutable reference to VCON and VOLT
/// and VOLT requires Core to be created in order for construction to succeed
/// In order to satisfy the above constraints, this contract was created
contract CoreDeploy {

    /// @notice event emitted when VCON is deployed
    event VCONDeployed(Vcon vcon);
    event VCONCore(address vcon);

    event vconbytecodehash(bytes32 hash);
    event voltbytecodehash(bytes32 hash);

    /// @notice event emitted when VOLT is deployed
    event VOLTDeployed(Volt volt);
    event VOLTCore(address volt);

    /// @notice immutable since these contracts do not change
    bytes32 immutable voltBytecodehash = 0x969e644e9523a84ffba2b7ed6f3eef0f7b1e00f1eef404e3e3cb6ae083886c84;
    bytes32 immutable vconBytecodehash = 0x69521bcb652ecdfcdbfaa75f426553fa9cadf62ff7e5c99823396a590923cd46;

    /// @notice og's only
    bytes32 immutable salt = 0xf17123bd04a8886cf5a696482c7a6db7c8632da161297864a7a3dbc37c811d0a;

    /// @notice helper function for deployment
    /// @return the address of the future VCON token
    function getFutureVCONAddress() public view returns(address) {
        return Create2.computeAddress(salt, vconBytecodehash);
    }

    /// @notice helper function for deployment
    /// @return the address of the future VOLT token
    function getFutureVOLTAddress() public view returns(address) {
        return Create2.computeAddress(salt, voltBytecodehash);
    }

    /// @notice helper function that leverages Create2 to deploy the VOLT system
    /// this function is needed to wire together the VOLT, VCON and Core contracts as VOLT relies on Core on construction,
    /// and core needs the VOLT & VCON addresses at construction, otherwise those variables cannot be immutable
    function deploy() external returns (Core core) {
        address futureVCONAddress = getFutureVCONAddress();
        address futureVOLTAddress = getFutureVOLTAddress();

        core = Core(Create2.deploy(0, salt, abi.encodePacked(type(Core).creationCode, abi.encode(futureVOLTAddress, futureVCONAddress))));
        Volt volt = Volt(Create2.deploy(0, salt, abi.encodePacked(type(Volt).creationCode, abi.encode(address(core)))));
        emit VOLTDeployed(volt);
        emit VOLTCore(address(core.volt()));

        /// grant msg.sender all VCON + VCON minting capabilities
        Vcon vcon = Vcon(Create2.deploy(0, salt, abi.encodePacked(type(Vcon).creationCode, abi.encode(msg.sender, msg.sender))));
        emit VCONDeployed(vcon);
        emit VCONCore(address(core.vcon()));

        bytes32 VCONbytecodehash;
        bytes32 VOLTbytecodehash;
        address vconAddress = address(vcon);
        address voltAddress = address(volt);

        assembly {
            VCONbytecodehash := extcodehash(vconAddress)
            VOLTbytecodehash := extcodehash(voltAddress)
        }
        emit vconbytecodehash(VCONbytecodehash);
        emit voltbytecodehash(VOLTbytecodehash);

        /// give governor role to the deployer
        core.grantGovernor(msg.sender);
        /// revoke governor role from this deployer smart contract
        core.revokeGovernor(address(this));

        // require(Address.isContract(address(volt)), "VOLT not deployed");
        // require(Address.isContract(address(vcon)), "VCON not deployed");
        // require(Address.isContract(address(core.volt())), "VOLT not deployed");
        // require(Address.isContract(address(core.vcon())), "VCON not deployed");
    }
}
