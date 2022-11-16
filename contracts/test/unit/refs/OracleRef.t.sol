/// // SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import {ICoreV2} from "../../../core/ICoreV2.sol";
import {MockOracle} from "../../../mock/MockOracle.sol";
import {MockOracleRef} from "../../../mock/MockOracleRef.sol";
import {Test, console2} from "../../../../forge-std/src/Test.sol";
import {VoltSystemOracle} from "../../../oracle/VoltSystemOracle.sol";
import {OraclePassThrough} from "../../../oracle/OraclePassThrough.sol";
import {getCoreV2, getAddresses, getLocalOracleSystem, VoltTestAddresses} from "./../../unit/utils/Fixtures.sol";

contract UnitTestOracleRef is Test {
    uint128 voltStartingPrice = 1.01e18;

    ICoreV2 private core;
    MockOracleRef private oracleRef;
    VoltTestAddresses public addresses = getAddresses();
    OraclePassThrough public oracle;
    bool public constant doInvert = false;
    int256 public constant decimalsNormalizer = 0;

    function setUp() public {
        core = getCoreV2();
        (, oracle) = getLocalOracleSystem(voltStartingPrice);
        oracleRef = new MockOracleRef(
            address(core),
            address(oracle),
            address(0),
            decimalsNormalizer,
            doInvert
        );
    }

    function testSetup() public {
        assertEq(oracleRef.doInvert(), doInvert);
        assertEq(oracleRef.decimalsNormalizer(), decimalsNormalizer);
        assertEq(address(core), address(oracleRef.core()));
        assertEq(oracleRef.readOracle().value, voltStartingPrice);
        assertEq(address(oracleRef.backupOracle()), address(0));
        assertEq(address(oracleRef.oracle()), address(oracle));
    }

    function testUpdateOracleNoOp() public {
        oracleRef.updateOracle();
    }

    function testInvalidPriceReverts() public {
        MockOracle newOracle = new MockOracle();
        newOracle.setValues(1.02e18, false);
        vm.prank(addresses.governorAddress);
        oracleRef.setOracle(address(newOracle));
        assertEq(address(oracleRef.oracle()), address(newOracle));
        (, bool valid) = newOracle.read();
        assertTrue(!valid);
        vm.expectRevert("OracleRef: oracle invalid");
        oracleRef.readOracle();
    }

    function testSetOracleGovernorSucceeds() public {
        address newOracle = address(12345);
        vm.prank(addresses.governorAddress);
        oracleRef.setOracle(newOracle);
        assertEq(address(oracleRef.oracle()), newOracle);
        assertEq(address(oracleRef.backupOracle()), address(0)); /// hasn't changed
    }

    function testSetBackupOracleGovernorSucceeds() public {
        address newOracle = address(12345);
        vm.prank(addresses.governorAddress);
        oracleRef.setBackupOracle(newOracle);
        assertEq(address(oracleRef.backupOracle()), newOracle);
        assertEq(address(oracleRef.oracle()), address(oracle)); /// hasn't changed
    }

    function testSetOracleAddressZeroGovernorFails() public {
        address newOracle = address(0);
        vm.prank(addresses.governorAddress);
        vm.expectRevert("OracleRef: zero address");
        oracleRef.setOracle(newOracle);
    }

    /// --------- ACL TESTS ---------

    function testSetOracleAddressNonGovernorFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        oracleRef.setOracle(address(0));
    }

    function testSetBackupOracleAddressNonGovernorFails() public {
        vm.expectRevert("CoreRef: Caller is not a governor");
        oracleRef.setBackupOracle(address(0));
    }
}
