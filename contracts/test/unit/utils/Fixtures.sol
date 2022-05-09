// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Core, Vcon, Volt, IERC20} from "../../../core/Core.sol";
import {DSTest} from "./DSTest.sol";
import {Vm} from "./Vm.sol";

struct FeiTestAddresses {
    address userAddress;
    address secondUserAddress;
    address beneficiaryAddress1;
    address beneficiaryAddress2;
    address governorAddress;
    address genesisGroup;
    address keeperAddress;
    address pcvControllerAddress;
    address minterAddress;
    address burnerAddress;
    address guardianAddress;
    address voltGovernorAddress;
    address voltDeployerAddress;
}

/// @dev Get a list of addresses
function getAddresses() pure returns (FeiTestAddresses memory) {
    FeiTestAddresses memory addresses = FeiTestAddresses({
        userAddress: address(0x1),
        secondUserAddress: address(0x2),
        beneficiaryAddress1: address(0x3),
        beneficiaryAddress2: address(0x4),
        governorAddress: address(0x5),
        genesisGroup: address(0x6),
        keeperAddress: address(0x7),
        pcvControllerAddress: address(0x8),
        minterAddress: address(0x9),
        burnerAddress: address(0x10),
        guardianAddress: address(0x11),
        voltGovernorAddress: address(0x12),
        voltDeployerAddress: address(0x13)
    });

    return addresses;
}

/// @dev Get a list of addresses
function getMainnetAddresses() pure returns (FeiTestAddresses memory) {
    FeiTestAddresses memory addresses = FeiTestAddresses({
        userAddress: address(0x1),
        secondUserAddress: address(0x2),
        beneficiaryAddress1: address(0x3),
        beneficiaryAddress2: address(0x4),
        governorAddress: address(0xd51dbA7a94e1adEa403553A8235C302cEbF41a3c),
        genesisGroup: address(0x6),
        keeperAddress: address(0x7),
        pcvControllerAddress: address(
            0xd51dbA7a94e1adEa403553A8235C302cEbF41a3c
        ),
        minterAddress: address(0xd51dbA7a94e1adEa403553A8235C302cEbF41a3c),
        burnerAddress: address(0x10),
        guardianAddress: address(0xEC7AD284f7Ad256b64c6E69b84Eb0F48f42e8196),
        voltGovernorAddress: address(
            0xcBB83206698E8788F85EFbEeeCAd17e53366EBDf
        ),
        voltDeployerAddress: address(0x25dCffa22EEDbF0A69F6277e24C459108c186ecB)
    });

    return addresses;
}

/// @dev Deploy and configure Core
function getCore() returns (Core) {
    address HEVM_ADDRESS = address(
        bytes20(uint160(uint256(keccak256("hevm cheat code"))))
    );
    Vm vm = Vm(HEVM_ADDRESS);
    FeiTestAddresses memory addresses = getAddresses();

    // Deploy Core from Governor address
    vm.startPrank(addresses.governorAddress);
    Core core = new Core();
    core.init();
    Vcon vcon = new Vcon(addresses.governorAddress, addresses.governorAddress);

    core.setVcon(IERC20(address(vcon)));
    core.grantMinter(addresses.minterAddress);
    core.grantBurner(addresses.burnerAddress);
    core.grantPCVController(addresses.pcvControllerAddress);
    core.grantGuardian(addresses.guardianAddress);

    vm.stopPrank();
    return core;
}
