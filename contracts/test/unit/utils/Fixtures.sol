// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {Vm} from "../../../../forge-std/src/Test.sol";
import {CoreV2} from "../../../core/CoreV2.sol";
import {MockERC20} from "./../../../mock/MockERC20.sol";
import {GenericCallMock} from "./../../../mock/GenericCallMock.sol";
import {VoltSystemOracle} from "../../../oracle/VoltSystemOracle.sol";
import {IOraclePassThrough} from "../../../oracle/IOraclePassThrough.sol";
import {IScalingPriceOracle} from "../../../oracle/IScalingPriceOracle.sol";
import {TestAddresses} from "./TestAddresses.sol";
import {Core, Vcon, Volt, IERC20, IVolt} from "../../../core/Core.sol";

struct VoltTestAddresses {
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

struct VoltAddresses {
    address pcvGuardAddress1; // address(0xf8D0387538E8e03F3B4394dA89f221D7565a28Ee),
    address pcvGuardAddress2; // address(0xd90E9181B20D8D1B5034d9f5737804Da182039F6),
    address executorAddress; // address(0xcBB83206698E8788F85EFbEeeCAd17e53366EBDf) // msig is executor
}

function getVoltAddresses() pure returns (VoltAddresses memory addresses) {
    addresses = VoltAddresses({
        pcvGuardAddress1: 0xf8D0387538E8e03F3B4394dA89f221D7565a28Ee,
        pcvGuardAddress2: 0xd90E9181B20D8D1B5034d9f5737804Da182039F6,
        executorAddress: 0xcBB83206698E8788F85EFbEeeCAd17e53366EBDf
    });
}

/// @dev Get a list of addresses
function getMainnetAddresses() pure returns (VoltTestAddresses memory) {
    VoltTestAddresses memory addresses = VoltTestAddresses({
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
        guardianAddress: address(0x2c2b362e6ae0F080F39b90Cb5657E5550090D6C3),
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

    // Deploy Core from Governor address
    vm.startPrank(TestAddresses.governorAddress);
    Core core = new Core();
    core.init();
    Vcon vcon = new Vcon(
        TestAddresses.governorAddress,
        TestAddresses.governorAddress
    );

    core.setVcon(IERC20(address(vcon)));
    core.grantMinter(TestAddresses.minterAddress);
    core.grantBurner(TestAddresses.burnerAddress);
    core.grantPCVController(TestAddresses.pcvControllerAddress);
    core.grantGuardian(TestAddresses.guardianAddress);

    vm.stopPrank();
    return core;
}

/// @dev Deploy and configure Core
function getCoreV2() returns (CoreV2) {
    address HEVM_ADDRESS = address(
        bytes20(uint160(uint256(keccak256("hevm cheat code"))))
    );
    Vm vm = Vm(HEVM_ADDRESS);

    MockERC20 volt = new MockERC20();
    // Deploy Core from Governor address
    vm.startPrank(TestAddresses.governorAddress);
    CoreV2 core = new CoreV2(address(volt));
    Vcon vcon = new Vcon(
        TestAddresses.governorAddress,
        TestAddresses.governorAddress
    );

    core.setVcon(IERC20(address(vcon)));
    core.grantMinter(TestAddresses.minterAddress);
    core.grantPCVController(TestAddresses.pcvControllerAddress);
    core.grantGuardian(TestAddresses.guardianAddress);

    vm.stopPrank();
    return core;
}

function getVoltSystemOracle(
    address _core,
    uint256 _monthlyChangeRate,
    uint32 _periodStartTime,
    uint224 _oraclePrice
) returns (VoltSystemOracle) {
    address HEVM_ADDRESS = address(
        bytes20(uint160(uint256(keccak256("hevm cheat code"))))
    );
    Vm vm = Vm(HEVM_ADDRESS);

    GenericCallMock mock = new GenericCallMock();
    VoltSystemOracle oracle = new VoltSystemOracle(_core);

    uint256 oraclePrice = _oraclePrice;
    mock.setResponseToCall(
        address(0),
        "",
        abi.encode(oraclePrice),
        bytes4(keccak256("getCurrentOraclePrice()"))
    );

    uint256 currentTimeStamp = block.timestamp;
    vm.warp(_periodStartTime);

    /// Initialize Core from Governor address
    vm.prank(TestAddresses.governorAddress);
    oracle.initialize(address(mock), _monthlyChangeRate);

    vm.warp(currentTimeStamp);

    return oracle;
}

function getOraclePassThrough(
    VoltSystemOracle oracle,
    address
) pure returns (IOraclePassThrough) {
    return IOraclePassThrough(address(oracle));
}

function getLocalOracleSystem(
    address core
) returns (VoltSystemOracle oracle, IOraclePassThrough opt) {
    oracle = getVoltSystemOracle(core, 100, uint32(block.timestamp), 1e18);
    opt = getOraclePassThrough(oracle, TestAddresses.governorAddress);
}

function getLocalOracleSystem(
    address core,
    uint200 startPrice
) returns (VoltSystemOracle oracle, IOraclePassThrough opt) {
    oracle = getVoltSystemOracle(
        core,
        100,
        uint32(block.timestamp),
        startPrice
    );
    opt = getOraclePassThrough(oracle, TestAddresses.governorAddress);
}
